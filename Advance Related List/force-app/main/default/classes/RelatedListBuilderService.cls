/**
 * @description Logic behind the Tekenable Related List Builder. Schema browsing uses the admin's describe
 *              results; validation reuses RelatedListSchemaService, the same code the list runs, so
 *              a definition that saves is one the list accepts. Saving builds Custom Metadata records
 *              and queues an Apex Metadata API deployment (Custom Metadata cannot be written with DML,
 *              and the Metadata API cannot delete records, so removed columns are flagged Removed__c).
 */
public with sharing class RelatedListBuilderService {
    public static final String ADMIN_PERMISSION = 'Advanced_Related_List_Admin';
    public static final Integer MAX_LABEL = 40;

    private static final Pattern DEV_NAME = Pattern.compile('^[A-Za-z](?!.*__)[A-Za-z0-9_]{0,39}(?<!_)$');
    private static final Pattern FLOW_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    private static final List<String> HIDDEN_SUFFIXES = new List<String>{ 'Feed', 'History', 'Share', 'ChangeEvent', '__mdt', '__e', '__b', '__hd', '__x' };

    /** Test seam: Apex tests cannot run Metadata API deployments. */
    @TestVisible
    private static Deployer deployer = new MetadataDeployer();
    @TestVisible
    private static Boolean adminPermissionOverride;

    /** @description Queues a metadata deployment. */
    public interface Deployer {
        /**
         * @description Queue the deployment.
         * @param container records to deploy
         * @return deployment job id
         */
        Id deploy(Metadata.DeployContainer container);
    }

    /** @description Real deployer: asynchronous Apex Metadata API deployment. */
    public class MetadataDeployer implements Deployer {
        /**
         * @description Queue the deployment.
         * @param container records to deploy
         * @return deployment job id
         */
        public Id deploy(Metadata.DeployContainer container) {
            return Metadata.Operations.enqueueDeployment(container, new DeployCallback());
        }
    }

    /** @description Deployment callback. Results are observed by polling the saved signature. */
    public class DeployCallback implements Metadata.DeployCallback {
        /**
         * @description Required by the interface; the UI polls getSignature for completion.
         * @param result deploy result
         * @param context callback context
         */
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
            return;
        }
    }

    // ===== ACCESS =====

    /**
     * @description Builder access: custom permission plus Customize Application.
     * @return access
     */
    public static RelatedListBuilderController.Access access() {
        RelatedListBuilderController.Access a = new RelatedListBuilderController.Access();
        Boolean hasCustom = Test.isRunningTest() && adminPermissionOverride != null ? adminPermissionOverride : FeatureManagement.checkPermission(ADMIN_PERMISSION);
        if (!hasCustom) {
            a.reason = 'You need the "Tekenable Advance Related List Admin" permission set to use the Tekenable Related List Builder.';
            return a;
        }
        Integer customize = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.PermissionsCustomizeApplication = true
            WITH SYSTEM_MODE
        ];
        if (customize == 0) {
            a.reason = 'You need the "Customize Application" permission to save list definitions.';
            return a;
        }
        a.canManage = true;
        return a;
    }

    // ===== READ =====

    /**
     * @description All definitions with active column counts.
     * @return summaries sorted by label
     */
    public static List<RelatedListBuilderController.DefinitionSummary> listDefinitions() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Advanced_Related_List_Column__mdt col : [
            SELECT Definition__r.DeveloperName
            FROM Advanced_Related_List_Column__mdt
            WHERE Removed__c = false
            WITH SYSTEM_MODE
        ]) {
            String key = col.Definition__r.DeveloperName;
            counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
        }
        List<String> order = new List<String>();
        Map<String, RelatedListBuilderController.DefinitionSummary> byKey = new Map<String, RelatedListBuilderController.DefinitionSummary>();
        for (Advanced_Related_List__mdt def : [
            SELECT DeveloperName, MasterLabel, Parent_Object__c, Child_Object__c, Relationship_Field__c, Active__c
            FROM Advanced_Related_List__mdt
            WITH SYSTEM_MODE
        ]) {
            RelatedListBuilderController.DefinitionSummary s = new RelatedListBuilderController.DefinitionSummary();
            s.developerName = def.DeveloperName;
            s.label = def.MasterLabel;
            s.parentObject = def.Parent_Object__c;
            s.childObject = def.Child_Object__c;
            s.lookupField = def.Relationship_Field__c;
            s.active = def.Active__c;
            s.columnCount = counts.containsKey(def.DeveloperName) ? counts.get(def.DeveloperName) : 0;
            String sortKey = (def.MasterLabel + '|' + def.DeveloperName).toLowerCase();
            order.add(sortKey);
            byKey.put(sortKey, s);
        }
        order.sort();
        List<RelatedListBuilderController.DefinitionSummary> result = new List<RelatedListBuilderController.DefinitionSummary>();
        for (String k : order) {
            result.add(byKey.get(k));
        }
        return result;
    }

    /**
     * @description Loads a definition and its active columns in display order.
     * @param developerName definition DeveloperName
     * @return draft with signature
     */
    public static RelatedListBuilderController.DefinitionDraft getDefinition(String developerName) {
        RelatedListBuilderController.DefinitionDraft draft = loadDraft(developerName);
        if (draft == null) {
            throw RelatedListException.config('List definition "' + developerName + '" was not found.');
        }
        return draft;
    }

    /**
     * @description Signature of the deployed definition, or null if it does not exist yet.
     * @param developerName DeveloperName
     * @return signature
     */
    public static String currentSignature(String developerName) {
        RelatedListBuilderController.DefinitionDraft draft = loadDraft(developerName);
        return draft == null ? null : draft.signature;
    }

    private static RelatedListBuilderController.DefinitionDraft loadDraft(String developerName) {
        if (String.isBlank(developerName) || !DEV_NAME.matcher(developerName).matches()) {
            return null;
        }
        List<Advanced_Related_List__mdt> defs = [
            SELECT
                DeveloperName,
                MasterLabel,
                Active__c,
                Parent_Object__c,
                Child_Object__c,
                Relationship_Field__c,
                Default_Sort_Field__c,
                Default_Sort_Direction__c,
                Allow_Create__c,
                Allow_Edit__c,
                Allow_Delete__c,
                Allow_Bulk_Delete__c,
                Flow_API_Name__c
            FROM Advanced_Related_List__mdt
            WHERE DeveloperName = :developerName
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (defs.isEmpty()) {
            return null;
        }
        Advanced_Related_List__mdt def = defs[0];
        RelatedListBuilderController.DefinitionDraft d = new RelatedListBuilderController.DefinitionDraft();
        d.developerName = def.DeveloperName;
        d.isNew = false;
        d.label = def.MasterLabel;
        d.active = def.Active__c;
        d.parentObject = def.Parent_Object__c;
        d.childObject = def.Child_Object__c;
        d.lookupField = def.Relationship_Field__c;
        d.defaultSortField = def.Default_Sort_Field__c;
        d.defaultSortDirection = def.Default_Sort_Direction__c;
        d.allowCreate = def.Allow_Create__c;
        d.allowEdit = def.Allow_Edit__c;
        d.allowDelete = def.Allow_Delete__c;
        d.allowBulkDelete = def.Allow_Bulk_Delete__c;
        d.flowApiName = def.Flow_API_Name__c;
        d.columns = new List<RelatedListBuilderController.ColumnDraft>();
        for (Advanced_Related_List_Column__mdt col : orderedColumns(developerName, false)) {
            d.columns.add(toColumnDraft(col));
        }
        d.actions = new List<RelatedListBuilderController.ActionDraft>();
        Boolean legacyFlowListed = String.isBlank(def.Flow_API_Name__c);
        for (Advanced_Related_List_Action__mdt act : orderedActions(developerName, false)) {
            d.actions.add(toActionDraft(act));
            if (act.Action_Type__c == RelatedListDefinitions.ACTION_FLOW && act.Target__c.equalsIgnoreCase(def.Flow_API_Name__c)) {
                legacyFlowListed = true;
            }
        }
        // The single legacy Flow field is shown as a header action; saving moves it into an action record.
        if (!legacyFlowListed) {
            RelatedListBuilderController.ActionDraft legacy = new RelatedListBuilderController.ActionDraft();
            legacy.actionType = RelatedListDefinitions.ACTION_FLOW;
            legacy.target = def.Flow_API_Name__c;
            legacy.placement = RelatedListDefinitions.PLACEMENT_LIST;
            if (d.actions.isEmpty()) {
                d.actions.add(legacy);
            } else {
                d.actions.add(0, legacy);
            }
        }
        // Lists from before New became an action row: show New where it appeared (after the others).
        if (def.Allow_Create__c && !hasStandardNew(d.actions)) {
            d.actions.add(newActionDraft());
        }
        d.flowApiName = null;
        d.signature = signatureOf(d);
        return d;
    }

    private static Boolean hasStandardNew(List<RelatedListBuilderController.ActionDraft> actions) {
        for (RelatedListBuilderController.ActionDraft a : actions) {
            if (a.actionType == RelatedListDefinitions.ACTION_STANDARD) {
                return true;
            }
        }
        return false;
    }

    private static RelatedListBuilderController.ActionDraft newActionDraft() {
        RelatedListBuilderController.ActionDraft a = new RelatedListBuilderController.ActionDraft();
        a.actionType = RelatedListDefinitions.ACTION_STANDARD;
        a.target = RelatedListDefinitions.STANDARD_NEW;
        a.placement = RelatedListDefinitions.PLACEMENT_LIST;
        a.display = RelatedListDefinitions.DISPLAY_BUTTON;
        return a;
    }

    private static List<Advanced_Related_List_Action__mdt> orderedActions(String developerName, Boolean includeRemoved) {
        List<String> keys = new List<String>();
        Map<String, Advanced_Related_List_Action__mdt> byKey = new Map<String, Advanced_Related_List_Action__mdt>();
        for (Advanced_Related_List_Action__mdt act : [
            SELECT DeveloperName, MasterLabel, Action_Type__c, Target__c, Label__c, Placement__c, Display__c, Order__c, Removed__c
            FROM Advanced_Related_List_Action__mdt
            WHERE Definition__r.DeveloperName = :developerName
            WITH SYSTEM_MODE
        ]) {
            if (act.Removed__c && !includeRemoved) {
                continue;
            }
            Decimal ord = act.Order__c == null ? 99999 : act.Order__c;
            String key = String.valueOf(ord.intValue() + 100000).leftPad(8, '0') + '|' + act.DeveloperName;
            keys.add(key);
            byKey.put(key, act);
        }
        keys.sort();
        List<Advanced_Related_List_Action__mdt> result = new List<Advanced_Related_List_Action__mdt>();
        for (String k : keys) {
            result.add(byKey.get(k));
        }
        return result;
    }

    private static RelatedListBuilderController.ActionDraft toActionDraft(Advanced_Related_List_Action__mdt act) {
        RelatedListBuilderController.ActionDraft a = new RelatedListBuilderController.ActionDraft();
        a.developerName = act.DeveloperName;
        a.actionType = act.Action_Type__c;
        a.target = act.Target__c;
        a.label = act.Label__c;
        a.placement = act.Placement__c;
        a.display = act.Display__c;
        return a;
    }

    private static List<Advanced_Related_List_Column__mdt> orderedColumns(String developerName, Boolean includeRemoved) {
        List<Advanced_Related_List_Column__mdt> cols = [
            SELECT
                DeveloperName,
                MasterLabel,
                Field_Path__c,
                Label__c,
                Order__c,
                Visible__c,
                Searchable__c,
                Filterable__c,
                Sortable__c,
                Editable__c,
                Removed__c
            FROM Advanced_Related_List_Column__mdt
            WHERE Definition__r.DeveloperName = :developerName
            WITH SYSTEM_MODE
        ];
        List<String> keys = new List<String>();
        Map<String, Advanced_Related_List_Column__mdt> byKey = new Map<String, Advanced_Related_List_Column__mdt>();
        for (Advanced_Related_List_Column__mdt col : cols) {
            if (col.Removed__c && !includeRemoved) {
                continue;
            }
            Decimal ord = col.Order__c == null ? 99999 : col.Order__c;
            String key = String.valueOf(ord.intValue() + 100000).leftPad(8, '0') + '|' + col.DeveloperName;
            keys.add(key);
            byKey.put(key, col);
        }
        keys.sort();
        List<Advanced_Related_List_Column__mdt> result = new List<Advanced_Related_List_Column__mdt>();
        for (String k : keys) {
            result.add(byKey.get(k));
        }
        return result;
    }

    private static RelatedListBuilderController.ColumnDraft toColumnDraft(Advanced_Related_List_Column__mdt col) {
        RelatedListBuilderController.ColumnDraft c = new RelatedListBuilderController.ColumnDraft();
        c.developerName = col.DeveloperName;
        c.fieldPath = col.Field_Path__c;
        c.label = col.Label__c;
        c.visible = col.Visible__c;
        c.searchable = col.Searchable__c;
        c.filterable = col.Filterable__c;
        c.sortable = col.Sortable__c;
        c.editable = col.Editable__c;
        return c;
    }

    // ===== SCHEMA BROWSING =====

    /**
     * @description Objects that have record pages (parent candidates), sorted by label.
     * @return options
     */
    public static List<RelatedListBuilderController.Option> listObjects() {
        List<String> keys = new List<String>();
        Map<String, RelatedListBuilderController.Option> byKey = new Map<String, RelatedListBuilderController.Option>();
        // EntityDefinition does not support queryMore: read it in keyset pages of 200.
        String lastName = '';
        for (Integer page = 0; page < 25; page++) {
            List<EntityDefinition> batch = [
                SELECT QualifiedApiName, Label
                FROM EntityDefinition
                WHERE IsQueryable = TRUE AND IsLayoutable = TRUE AND IsCustomSetting = FALSE AND IsDeprecatedAndHidden = FALSE AND QualifiedApiName > :lastName
                WITH USER_MODE
                ORDER BY QualifiedApiName
                LIMIT 200
            ];
            for (EntityDefinition e : batch) {
                lastName = e.QualifiedApiName;
                if (isHidden(e.QualifiedApiName)) {
                    continue;
                }
                String key = (e.Label + '|' + e.QualifiedApiName).toLowerCase();
                keys.add(key);
                byKey.put(key, new RelatedListBuilderController.Option(e.Label, e.QualifiedApiName, e.QualifiedApiName));
            }
            if (batch.size() < 200) {
                break;
            }
        }
        keys.sort();
        List<RelatedListBuilderController.Option> result = new List<RelatedListBuilderController.Option>();
        for (String k : keys) {
            result.add(byKey.get(k));
        }
        return result;
    }

    /**
     * @description Child relationships (child object + lookup) the list can show for a parent.
     * @param parentObject parent API name
     * @return relationships
     */
    public static List<RelatedListBuilderController.RelationshipOption> listRelationships(String parentObject) {
        Schema.DescribeSObjectResult parent = RelatedListSchemaService.describeObject(parentObject, 'Parent object');
        List<String> keys = new List<String>();
        Map<String, RelatedListBuilderController.RelationshipOption> byKey = new Map<String, RelatedListBuilderController.RelationshipOption>();
        for (Schema.ChildRelationship cr : parent.getChildRelationships()) {
            if (cr.isDeprecatedAndHidden() || cr.getField() == null) {
                continue;
            }
            Schema.DescribeSObjectResult child = cr.getChildSObject().getDescribe(SObjectDescribeOptions.DEFERRED);
            if (isHidden(child.getName()) || !child.isAccessible() || !child.isQueryable()) {
                continue;
            }
            Schema.DescribeFieldResult lookup = cr.getField().getDescribe();
            if (!lookup.isAccessible() || !lookup.isFilterable()) {
                continue;
            }
            RelatedListBuilderController.RelationshipOption o = new RelatedListBuilderController.RelationshipOption();
            o.childObject = child.getName();
            o.childLabel = child.getLabelPlural();
            o.lookupField = lookup.getName();
            o.lookupLabel = lookup.getLabel();
            o.value = o.childObject + '.' + o.lookupField;
            o.label = o.childLabel + ' (via ' + o.lookupLabel + ')';
            String key = (o.childLabel + '|' + o.lookupLabel + '|' + o.value).toLowerCase();
            if (!byKey.containsKey(key)) {
                keys.add(key);
                byKey.put(key, o);
            }
        }
        keys.sort();
        List<RelatedListBuilderController.RelationshipOption> result = new List<RelatedListBuilderController.RelationshipOption>();
        for (String k : keys) {
            result.add(byKey.get(k));
        }
        return result;
    }

    /**
     * @description Readable fields of an object with list capabilities.
     * @param objectApiName object
     * @return fields
     */
    public static List<RelatedListBuilderController.FieldOption> listFields(String objectApiName) {
        Schema.DescribeSObjectResult obj = RelatedListSchemaService.describeObject(objectApiName, 'Object');
        List<String> keys = new List<String>();
        Map<String, RelatedListBuilderController.FieldOption> byKey = new Map<String, RelatedListBuilderController.FieldOption>();
        for (Schema.SObjectField f : obj.fields.getMap().values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (!dfr.isAccessible() || dfr.getType() == Schema.DisplayType.BASE64) {
                continue;
            }
            RelatedListBuilderController.FieldOption o = new RelatedListBuilderController.FieldOption();
            o.apiName = dfr.getName();
            o.label = dfr.getLabel();
            o.type = String.valueOf(dfr.getType());
            o.canSearch = RelatedListSchemaService.supportsSearch(dfr);
            o.canFilter = RelatedListSchemaService.supportsFilter(dfr);
            o.canSort = RelatedListSchemaService.supportsSort(dfr);
            o.canEdit = dfr.isUpdateable();
            List<Schema.SObjectType> targets = dfr.getReferenceTo();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.getRelationshipName() != null && targets.size() == 1) {
                Schema.DescribeSObjectResult target = targets[0].getDescribe(SObjectDescribeOptions.DEFERRED);
                if (target.isAccessible()) {
                    o.relationshipName = dfr.getRelationshipName();
                    o.targetObject = target.getName();
                    o.targetLabel = target.getLabel();
                }
            }
            String key = (o.label + '|' + o.apiName).toLowerCase();
            keys.add(key);
            byKey.put(key, o);
        }
        keys.sort();
        List<RelatedListBuilderController.FieldOption> result = new List<RelatedListBuilderController.FieldOption>();
        for (String k : keys) {
            result.add(byKey.get(k));
        }
        return result;
    }

    /**
     * @description Active screen flows.
     * @return options
     */
    public static List<RelatedListBuilderController.Option> listFlows() {
        List<RelatedListBuilderController.Option> result = new List<RelatedListBuilderController.Option>();
        try {
            for (FlowDefinitionView f : [
                SELECT ApiName, Label
                FROM FlowDefinitionView
                WHERE ProcessType = 'Flow' AND IsActive = TRUE
                WITH USER_MODE
                ORDER BY Label
                LIMIT 500
            ]) {
                result.add(new RelatedListBuilderController.Option(f.Label, f.ApiName, f.ApiName));
            }
        } catch (Exception e) {
            return result;
        }
        return result;
    }

    /** Quick action types that cannot be launched from a list (feed publisher actions). */
    private static final Set<String> UNLAUNCHABLE_ACTION_TYPES = new Set<String>{ 'Post' };

    /**
     * @description Launchable quick actions Salesforce reports as available for an object.
     * @param objectApiName object (parent for header buttons, child for row items)
     * @return options sorted by label: value = action name, description = type
     */
    public static List<RelatedListBuilderController.Option> listQuickActions(String objectApiName) {
        Schema.DescribeSObjectResult obj = RelatedListSchemaService.describeObject(objectApiName, 'Object');
        List<String> keys = new List<String>();
        Map<String, RelatedListBuilderController.Option> byKey = new Map<String, RelatedListBuilderController.Option>();
        for (QuickAction.DescribeAvailableQuickActionResult r : QuickAction.describeAvailableQuickActions(obj.getName())) {
            if (UNLAUNCHABLE_ACTION_TYPES.contains(r.getType()) || r.getName().startsWith('FeedItem.')) {
                continue;
            }
            String key = (r.getLabel() + '|' + r.getName()).toLowerCase();
            keys.add(key);
            byKey.put(key, new RelatedListBuilderController.Option(r.getLabel(), r.getName(), r.getType()));
        }
        keys.sort();
        List<RelatedListBuilderController.Option> result = new List<RelatedListBuilderController.Option>();
        for (String k : keys) {
            result.add(byKey.get(k));
        }
        return result;
    }

    private static Boolean isHidden(String apiName) {
        for (String suffix : HIDDEN_SUFFIXES) {
            if (apiName.endsWith(suffix)) {
                return true;
            }
        }
        return false;
    }

    // ===== VALIDATION =====

    /**
     * @description Validates a draft. Errors block saving; warnings do not.
     * @param draft draft
     * @return result
     */
    public static RelatedListBuilderController.ValidationResult validate(RelatedListBuilderController.DefinitionDraft draft) {
        RelatedListBuilderController.ValidationResult vr = new RelatedListBuilderController.ValidationResult();
        if (draft == null) {
            addError(vr, 'The definition is empty.', null);
            return vr;
        }
        normalize(draft);

        if (String.isBlank(draft.label)) {
            addError(vr, 'Enter a label.', null);
        } else if (draft.label.length() > MAX_LABEL) {
            addError(vr, 'The label can be up to ' + MAX_LABEL + ' characters.', null);
        }
        if (String.isBlank(draft.developerName) || !DEV_NAME.matcher(draft.developerName).matches()) {
            addError(vr, 'The API name must start with a letter, use only letters, numbers and single underscores, not end with an underscore, and be up to 40 characters.', null);
        } else if (draft.isNew == true && loadDraft(draft.developerName) != null) {
            addError(vr, 'A list definition named "' + draft.developerName + '" already exists. Choose another API name.', null);
        } else if (draft.isNew != true && loadDraft(draft.developerName) == null) {
            addError(vr, 'List definition "' + draft.developerName + '" no longer exists. Reload the builder.', null);
        }

        Schema.DescribeSObjectResult parent = null;
        Schema.DescribeSObjectResult child = null;
        if (String.isBlank(draft.parentObject)) {
            addError(vr, 'Choose the record page object.', null);
        } else {
            try {
                parent = RelatedListSchemaService.describeObject(draft.parentObject, 'Parent object');
            } catch (RelatedListException e) {
                addError(vr, e.getMessage(), null);
            }
        }
        if (String.isBlank(draft.childObject) || String.isBlank(draft.lookupField)) {
            addError(vr, 'Choose which related records to show.', null);
        } else {
            try {
                child = RelatedListSchemaService.describeObject(draft.childObject, 'Child object');
            } catch (RelatedListException e) {
                addError(vr, e.getMessage(), null);
            }
        }

        List<RelatedListBuilderController.ColumnDraft> cols = draft.columns == null ? new List<RelatedListBuilderController.ColumnDraft>() : draft.columns;
        if (cols.isEmpty()) {
            addError(vr, 'Add at least one column.', null);
        }
        if (cols.size() > RelatedListDefinitions.MAX_COLUMNS) {
            addError(vr, 'Use up to ' + RelatedListDefinitions.MAX_COLUMNS + ' columns.', null);
        }
        Boolean anyVisible = false;
        Set<String> seenPaths = new Set<String>();
        for (Integer i = 0; i < cols.size(); i++) {
            RelatedListBuilderController.ColumnDraft col = cols[i];
            anyVisible = anyVisible || col.visible == true;
            if (String.isBlank(col.fieldPath)) {
                addError(vr, 'Column ' + (i + 1) + ' has no field.', i);
                continue;
            }
            if (seenPaths.contains(col.fieldPath.toLowerCase())) {
                addError(vr, 'Column ' + (i + 1) + ' repeats the field "' + col.fieldPath + '".', i);
            }
            seenPaths.add(col.fieldPath.toLowerCase());
            if (col.label != null && col.label.length() > 80) {
                addError(vr, 'Column ' + (i + 1) + ': the label can be up to 80 characters.', i);
            }
            if (child != null) {
                validateColumn(vr, child, col, i);
            }
        }
        if (!cols.isEmpty() && !anyVisible) {
            addError(vr, 'Make at least one column visible.', null);
        }

        if (String.isNotBlank(draft.defaultSortField) && child != null) {
            try {
                RelatedListSchemaService.FieldPath fp = RelatedListSchemaService.resolvePath(child, draft.defaultSortField);
                if (!RelatedListSchemaService.supportsSort(fp.field)) {
                    addError(vr, 'The default sort field "' + draft.defaultSortField + '" cannot be sorted.', null);
                }
            } catch (RelatedListException e) {
                addError(vr, 'Default sort: ' + e.getMessage(), null);
            }
        }
        validateActions(vr, draft, parent, child);
        if (draft.allowBulkDelete == true) {
            addWarning(vr, 'Bulk delete also requires users to have the "Tekenable Advance Related List Bulk Delete" permission set.', null);
        }
        if (draft.active != true) {
            addWarning(vr, 'This definition is inactive. Pages that use it will show a configuration message.', null);
        }

        // Final check with the exact runtime resolver, only when the pieces above are sound.
        if (vr.valid && parent != null) {
            try {
                RelatedListSchemaService.ResolvedList rl = RelatedListSchemaService.resolveForParentType(toSpec(draft), parent.getSObjectType());
                if (rl.omittedCount > 0) {
                    addWarning(vr, rl.omittedCount + ' column(s) are hidden from you by field-level security. Users who can read those fields will see them.', null);
                }
            } catch (RelatedListException e) {
                addError(vr, e.getMessage(), null);
            }
        }
        return vr;
    }

    private static void validateColumn(RelatedListBuilderController.ValidationResult vr, Schema.DescribeSObjectResult child, RelatedListBuilderController.ColumnDraft col, Integer i) {
        String prefix = 'Column ' + (i + 1) + ' (' + col.fieldPath + '): ';
        RelatedListSchemaService.FieldPath fp;
        try {
            fp = RelatedListSchemaService.resolvePath(child, col.fieldPath);
        } catch (RelatedListException e) {
            addError(vr, prefix + e.getMessage(), i);
            return;
        }
        Schema.DescribeFieldResult dfr = fp.field;
        Boolean compound = dfr.getType() == Schema.DisplayType.ADDRESS || dfr.getType() == Schema.DisplayType.LOCATION;
        if (compound && fp.depth > 0) {
            addError(vr, prefix + 'address and location fields are only supported directly on the related object.', i);
        }
        if (dfr.getType() == Schema.DisplayType.BASE64) {
            addError(vr, prefix + 'this field type cannot be displayed.', i);
        }
        if (col.searchable == true && !RelatedListSchemaService.supportsSearch(dfr)) {
            addError(vr, prefix + 'this field type cannot be searched.', i);
        }
        if (col.filterable == true && !RelatedListSchemaService.supportsFilter(dfr)) {
            addError(vr, prefix + 'this field type cannot be filtered.', i);
        }
        if (col.sortable == true && !RelatedListSchemaService.supportsSort(dfr)) {
            addError(vr, prefix + 'this field type cannot be sorted.', i);
        }
        if (col.editable == true && fp.depth > 0) {
            addError(vr, prefix + 'fields on related records cannot be edited from this list.', i);
        }
        if (!fp.accessible) {
            addWarning(vr, prefix + 'you cannot read this field, so it is hidden from you. Users with access will see it.', i);
        }
    }

    private static void validateActions(
        RelatedListBuilderController.ValidationResult vr,
        RelatedListBuilderController.DefinitionDraft draft,
        Schema.DescribeSObjectResult parent,
        Schema.DescribeSObjectResult child
    ) {
        List<RelatedListBuilderController.ActionDraft> actions = draft.actions == null ? new List<RelatedListBuilderController.ActionDraft>() : draft.actions;
        if (actions.size() > RelatedListDefinitions.MAX_ACTIONS) {
            addError(vr, 'Use up to ' + RelatedListDefinitions.MAX_ACTIONS + ' actions.', null);
        }
        Map<String, Map<String, String>> quickByObject = new Map<String, Map<String, String>>();
        Set<String> seen = new Set<String>();
        for (Integer i = 0; i < actions.size(); i++) {
            RelatedListBuilderController.ActionDraft a = actions[i];
            String prefix = 'Action ' + (i + 1) + ': ';
            Boolean isList = a.placement == RelatedListDefinitions.PLACEMENT_LIST;
            if (!isList && a.placement != RelatedListDefinitions.PLACEMENT_ROW) {
                addActionError(vr, prefix + 'choose where it appears.', i);
                continue;
            }
            if (String.isBlank(a.target)) {
                addActionError(vr, prefix + 'choose the flow or quick action to run.', i);
                continue;
            }
            String identity = a.actionType + '|' + a.target.toLowerCase() + '|' + a.placement;
            if (seen.contains(identity)) {
                addActionError(vr, prefix + 'the same action is already in the same place.', i);
            }
            seen.add(identity);
            if (a.label != null && a.label.length() > 80) {
                addActionError(vr, prefix + 'the label can be up to 80 characters.', i);
            }
            if (a.display != null && a.display != RelatedListDefinitions.DISPLAY_BUTTON && a.display != RelatedListDefinitions.DISPLAY_MENU) {
                addActionError(vr, prefix + 'choose Button or More menu.', i);
            }
            if (a.actionType == RelatedListDefinitions.ACTION_STANDARD) {
                if (!RelatedListDefinitions.STANDARD_NEW.equalsIgnoreCase(a.target)) {
                    addActionError(vr, prefix + 'the only standard action is New.', i);
                } else if (!isList) {
                    addActionError(vr, prefix + 'New can only be a list header action.', i);
                } else if (child != null && !child.isCreateable()) {
                    RelatedListBuilderController.Issue w = new RelatedListBuilderController.Issue(
                        'warning',
                        prefix + 'you cannot create ' + child.getLabelPlural() + ', so you will not see New. Users who can create them will.',
                        null
                    );
                    w.actionIndex = i;
                    vr.issues.add(w);
                }
            } else if (a.actionType == RelatedListDefinitions.ACTION_FLOW) {
                if (!FLOW_NAME.matcher(a.target).matches()) {
                    addActionError(vr, prefix + 'the flow API name is not valid.', i);
                } else if (!flowExists(a.target)) {
                    RelatedListBuilderController.Issue w = new RelatedListBuilderController.Issue(
                        'warning',
                        prefix + 'no active screen flow named "' + a.target + '" was found. The button will show an error until it is active.',
                        null
                    );
                    w.actionIndex = i;
                    vr.issues.add(w);
                }
            } else if (a.actionType == RelatedListDefinitions.ACTION_QUICK) {
                Schema.DescribeSObjectResult context = isList ? parent : child;
                if (context == null) {
                    continue; // relationship errors are already reported
                }
                if (!quickByObject.containsKey(context.getName())) {
                    Map<String, String> names = new Map<String, String>();
                    for (RelatedListBuilderController.Option o : listQuickActions(context.getName())) {
                        names.put(o.value.toLowerCase(), o.label);
                    }
                    quickByObject.put(context.getName(), names);
                }
                if (!quickByObject.get(context.getName()).containsKey(a.target.toLowerCase())) {
                    addActionError(
                        vr,
                        prefix + 'quick action "' + a.target + '" is not available for ' + context.getLabel() + (isList ? ' (header buttons run for the record page record).' : ' (row items run for each related record).'),
                        i
                    );
                }
            } else {
                addActionError(vr, prefix + 'choose Flow or Quick Action.', i);
            }
        }
    }

    private static void addActionError(RelatedListBuilderController.ValidationResult vr, String message, Integer index) {
        RelatedListBuilderController.Issue issue = new RelatedListBuilderController.Issue('error', message, null);
        issue.actionIndex = index;
        vr.valid = false;
        vr.issues.add(issue);
    }

    private static Boolean flowExists(String apiName) {
        for (RelatedListBuilderController.Option o : listFlows()) {
            if (o.value == apiName) {
                return true;
            }
        }
        return false;
    }

    private static void addError(RelatedListBuilderController.ValidationResult vr, String message, Integer index) {
        vr.valid = false;
        vr.issues.add(new RelatedListBuilderController.Issue('error', message, index));
    }

    private static void addWarning(RelatedListBuilderController.ValidationResult vr, String message, Integer index) {
        vr.issues.add(new RelatedListBuilderController.Issue('warning', message, index));
    }

    // ===== SAVE =====

    /**
     * @description Validates and queues the deployment of the definition and its columns.
     * @param draft draft
     * @return save result
     */
    public static RelatedListBuilderController.SaveResult save(RelatedListBuilderController.DefinitionDraft draft) {
        RelatedListBuilderController.SaveResult result = new RelatedListBuilderController.SaveResult();
        RelatedListBuilderController.ValidationResult vr = validate(draft);
        result.issues = vr.issues;
        result.developerName = draft == null ? null : draft.developerName;
        if (!vr.valid) {
            result.status = 'INVALID';
            return result;
        }

        // Existing columns of this definition (including removed ones) keep their names; anything
        // else gets a new unique name. Columns dropped from the draft are flagged Removed__c.
        Map<String, Advanced_Related_List_Column__mdt> existing = new Map<String, Advanced_Related_List_Column__mdt>();
        if (draft.isNew != true) {
            for (Advanced_Related_List_Column__mdt col : orderedColumns(draft.developerName, true)) {
                existing.put(col.DeveloperName, col);
            }
        }
        Set<String> takenNames = new Set<String>();
        for (Advanced_Related_List_Column__mdt col : [SELECT DeveloperName FROM Advanced_Related_List_Column__mdt WITH SYSTEM_MODE]) {
            takenNames.add(col.DeveloperName.toLowerCase());
        }

        Metadata.DeployContainer container = new Metadata.DeployContainer();
        container.addMetadata(definitionRecord(draft));
        Set<String> kept = new Set<String>();
        for (Integer i = 0; i < draft.columns.size(); i++) {
            RelatedListBuilderController.ColumnDraft col = draft.columns[i];
            if (String.isBlank(col.developerName) || !existing.containsKey(col.developerName)) {
                col.developerName = uniqueColumnName(draft.developerName, col.fieldPath, takenNames);
            }
            takenNames.add(col.developerName.toLowerCase());
            kept.add(col.developerName);
            container.addMetadata(columnRecord(draft.developerName, col, (i + 1) * 10, false));
        }
        for (Advanced_Related_List_Column__mdt old : existing.values()) {
            if (!kept.contains(old.DeveloperName) && !old.Removed__c) {
                container.addMetadata(columnRecord(draft.developerName, toColumnDraft(old), old.Order__c == null ? 9990 : old.Order__c.intValue(), true));
            }
        }

        Map<String, Advanced_Related_List_Action__mdt> existingActions = new Map<String, Advanced_Related_List_Action__mdt>();
        if (draft.isNew != true) {
            for (Advanced_Related_List_Action__mdt act : orderedActions(draft.developerName, true)) {
                existingActions.put(act.DeveloperName, act);
            }
        }
        Set<String> takenActionNames = new Set<String>();
        for (Advanced_Related_List_Action__mdt act : [SELECT DeveloperName FROM Advanced_Related_List_Action__mdt WITH SYSTEM_MODE]) {
            takenActionNames.add(act.DeveloperName.toLowerCase());
        }
        Set<String> keptActions = new Set<String>();
        for (Integer i = 0; i < draft.actions.size(); i++) {
            RelatedListBuilderController.ActionDraft act = draft.actions[i];
            if (String.isBlank(act.developerName) || !existingActions.containsKey(act.developerName)) {
                act.developerName = uniqueColumnName(draft.developerName, 'Action_' + act.target, takenActionNames);
            }
            takenActionNames.add(act.developerName.toLowerCase());
            keptActions.add(act.developerName);
            container.addMetadata(actionRecord(draft.developerName, act, (i + 1) * 10, false));
        }
        for (Advanced_Related_List_Action__mdt old : existingActions.values()) {
            if (!keptActions.contains(old.DeveloperName) && !old.Removed__c) {
                container.addMetadata(actionRecord(draft.developerName, toActionDraft(old), old.Order__c == null ? 9990 : old.Order__c.intValue(), true));
            }
        }

        result.jobId = deployer.deploy(container);
        result.developerName = draft.developerName;
        result.signature = signatureOf(draft);
        result.status = 'QUEUED';
        return result;
    }

    private static Metadata.CustomMetadata definitionRecord(RelatedListBuilderController.DefinitionDraft d) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Advanced_Related_List.' + d.developerName;
        md.label = d.label;
        md.values.add(value('Active__c', d.active == true));
        md.values.add(value('Parent_Object__c', d.parentObject));
        md.values.add(value('Child_Object__c', d.childObject));
        md.values.add(value('Relationship_Field__c', d.lookupField));
        md.values.add(value('Default_Sort_Field__c', blankToNull(d.defaultSortField)));
        md.values.add(value('Default_Sort_Direction__c', d.defaultSortDirection));
        md.values.add(value('Allow_Create__c', d.allowCreate == true));
        md.values.add(value('Allow_Edit__c', d.allowEdit == true));
        md.values.add(value('Allow_Delete__c', d.allowDelete == true));
        md.values.add(value('Allow_Bulk_Delete__c', d.allowBulkDelete == true));
        // The single legacy Flow field is migrated into action records by the builder.
        md.values.add(value('Flow_API_Name__c', null));
        return md;
    }

    private static Metadata.CustomMetadata columnRecord(String definitionName, RelatedListBuilderController.ColumnDraft c, Integer order, Boolean removed) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Advanced_Related_List_Column.' + c.developerName;
        String label = String.isNotBlank(c.label) ? c.label : c.fieldPath;
        md.label = label.left(MAX_LABEL);
        md.values.add(value('Definition__c', definitionName));
        md.values.add(value('Field_Path__c', c.fieldPath));
        md.values.add(value('Label__c', blankToNull(c.label)));
        md.values.add(value('Order__c', Decimal.valueOf(order)));
        md.values.add(value('Visible__c', c.visible == true));
        md.values.add(value('Searchable__c', c.searchable == true));
        md.values.add(value('Filterable__c', c.filterable == true));
        md.values.add(value('Sortable__c', c.sortable == true));
        md.values.add(value('Editable__c', c.editable == true));
        md.values.add(value('Removed__c', removed));
        return md;
    }

    private static Metadata.CustomMetadata actionRecord(String definitionName, RelatedListBuilderController.ActionDraft a, Integer order, Boolean removed) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Advanced_Related_List_Action.' + a.developerName;
        String label = String.isNotBlank(a.label) ? a.label : a.target;
        md.label = label.left(MAX_LABEL);
        md.values.add(value('Definition__c', definitionName));
        md.values.add(value('Action_Type__c', a.actionType));
        md.values.add(value('Target__c', a.target));
        md.values.add(value('Label__c', blankToNull(a.label)));
        md.values.add(value('Placement__c', a.placement));
        md.values.add(value('Display__c', a.placement == RelatedListDefinitions.PLACEMENT_LIST ? blankToNull(a.display) : null));
        md.values.add(value('Order__c', Decimal.valueOf(order)));
        md.values.add(value('Removed__c', removed));
        return md;
    }

    private static Metadata.CustomMetadataValue value(String field, Object v) {
        Metadata.CustomMetadataValue cmv = new Metadata.CustomMetadataValue();
        cmv.field = field;
        cmv.value = v;
        return cmv;
    }

    // ===== NORMALISATION & NAMES =====

    @TestVisible
    private static void normalize(RelatedListBuilderController.DefinitionDraft d) {
        d.label = trimToNull(d.label);
        d.developerName = trimToNull(d.developerName);
        if (d.isNew == true && d.developerName == null && d.label != null) {
            d.developerName = developerNameFrom(d.label);
        }
        d.parentObject = trimToNull(d.parentObject);
        d.childObject = trimToNull(d.childObject);
        d.lookupField = trimToNull(d.lookupField);
        d.defaultSortField = trimToNull(d.defaultSortField);
        d.defaultSortDirection = 'DESC'.equalsIgnoreCase(d.defaultSortDirection) ? 'DESC' : 'ASC';
        if (d.actions == null) {
            d.actions = new List<RelatedListBuilderController.ActionDraft>();
        }
        for (RelatedListBuilderController.ActionDraft a : d.actions) {
            a.developerName = trimToNull(a.developerName);
            a.target = trimToNull(a.target);
            a.label = trimToNull(a.label);
            a.display = trimToNull(a.display);
            if (a.placement == RelatedListDefinitions.PLACEMENT_ROW) {
                a.display = null;
            }
        }
        // A client that still sends the single legacy flow gets it as a header action.
        String legacyFlow = trimToNull(d.flowApiName);
        if (legacyFlow != null) {
            Boolean present = false;
            for (RelatedListBuilderController.ActionDraft a : d.actions) {
                present = present || (a.actionType == RelatedListDefinitions.ACTION_FLOW && legacyFlow.equalsIgnoreCase(a.target));
            }
            if (!present) {
                RelatedListBuilderController.ActionDraft a = new RelatedListBuilderController.ActionDraft();
                a.actionType = RelatedListDefinitions.ACTION_FLOW;
                a.target = legacyFlow;
                a.placement = RelatedListDefinitions.PLACEMENT_LIST;
                d.actions.add(a);
            }
        }
        d.flowApiName = null;
        // New is an ordered action row; Allow_Create__c mirrors whether that row exists.
        if (d.allowCreate == true && !hasStandardNew(d.actions)) {
            d.actions.add(newActionDraft());
        }
        d.allowCreate = hasStandardNew(d.actions);
        if (d.columns == null) {
            d.columns = new List<RelatedListBuilderController.ColumnDraft>();
        }
        for (RelatedListBuilderController.ColumnDraft c : d.columns) {
            c.fieldPath = trimToNull(c.fieldPath);
            c.label = trimToNull(c.label);
            c.developerName = trimToNull(c.developerName);
        }
    }

    /**
     * @description Builds a valid DeveloperName from a label.
     * @param label label
     * @return developer name
     */
    public static String developerNameFrom(String label) {
        String s = label == null ? '' : label.replaceAll('[^A-Za-z0-9]+', '_');
        s = s.replaceAll('_+', '_').removeStart('_');
        if (s.length() == 0 || !s.substring(0, 1).isAlpha()) {
            s = 'L_' + s;
        }
        s = s.left(40);
        while (s.endsWith('_')) {
            s = s.removeEnd('_');
        }
        return s;
    }

    private static String uniqueColumnName(String definitionName, String fieldPath, Set<String> taken) {
        String base = developerNameFrom(definitionName.left(18) + '_' + fieldPath);
        String candidate = base;
        Integer n = 2;
        while (taken.contains(candidate.toLowerCase())) {
            String suffix = '_' + n++;
            candidate = developerNameFrom(base.left(40 - suffix.length())) + suffix;
        }
        return candidate;
    }

    // ===== SIGNATURE =====

    /**
     * @description Order-sensitive fingerprint of a definition's saved content.
     * @param d draft (normalized or loaded)
     * @return hex digest
     */
    public static String signatureOf(RelatedListBuilderController.DefinitionDraft d) {
        List<String> parts = new List<String>{
            str(d.label),
            String.valueOf(d.active == true),
            str(d.parentObject),
            str(d.childObject),
            str(d.lookupField),
            str(d.defaultSortField),
            'DESC'.equalsIgnoreCase(d.defaultSortDirection) ? 'DESC' : 'ASC',
            String.valueOf(d.allowCreate == true),
            String.valueOf(d.allowEdit == true),
            String.valueOf(d.allowDelete == true),
            String.valueOf(d.allowBulkDelete == true)
        };
        if (d.actions != null) {
            for (RelatedListBuilderController.ActionDraft a : d.actions) {
                parts.add('A:' + String.join(new List<String>{ str(a.developerName), str(a.actionType), str(a.target), str(a.label), str(a.placement), a.placement == RelatedListDefinitions.PLACEMENT_LIST ? str(a.display) : '' }, ','));
            }
        }
        if (d.columns != null) {
            for (RelatedListBuilderController.ColumnDraft c : d.columns) {
                parts.add(
                    String.join(
                        new List<String>{
                            str(c.developerName),
                            str(c.fieldPath),
                            str(c.label),
                            String.valueOf(c.visible == true),
                            String.valueOf(c.searchable == true),
                            String.valueOf(c.filterable == true),
                            String.valueOf(c.sortable == true),
                            String.valueOf(c.editable == true)
                        },
                        ','
                    )
                );
            }
        }
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(parts, '|'))));
    }

    private static String str(String v) {
        return v == null ? '' : v.trim();
    }

    private static String trimToNull(String v) {
        return String.isBlank(v) ? null : v.trim();
    }

    private static String blankToNull(String v) {
        return String.isBlank(v) ? null : v;
    }

    private static RelatedListDefinitions.ListSpec toSpec(RelatedListBuilderController.DefinitionDraft d) {
        RelatedListDefinitions.ListSpec spec = new RelatedListDefinitions.ListSpec();
        spec.mode = RelatedListDefinitions.MODE_DEFINITION;
        spec.definitionKey = d.developerName;
        spec.active = true;
        spec.parentObject = d.parentObject;
        spec.childObject = d.childObject;
        spec.lookupField = d.lookupField;
        spec.defaultSortField = d.defaultSortField;
        spec.defaultSortDirection = d.defaultSortDirection;
        spec.allowCreate = d.allowCreate == true;
        spec.allowEdit = d.allowEdit == true;
        spec.allowDelete = d.allowDelete == true;
        spec.allowBulkDelete = d.allowBulkDelete == true;
        spec.flowApiName = d.flowApiName;
        Integer i = 0;
        for (RelatedListBuilderController.ColumnDraft c : d.columns) {
            RelatedListDefinitions.ColumnSpec cs = new RelatedListDefinitions.ColumnSpec('b' + i++, c.fieldPath);
            cs.label = c.label;
            cs.visible = c.visible == true;
            cs.searchable = c.searchable == true;
            cs.filterable = c.filterable == true;
            cs.sortable = c.sortable == true;
            cs.editable = c.editable == true;
            spec.columns.add(cs);
        }
        return spec;
    }
}
