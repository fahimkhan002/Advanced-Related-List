/**
 * @description Loads list definitions (Custom Metadata) or maps legacy App Builder properties into
 *              one unvalidated ListSpec. All schema and permission validation happens later in
 *              RelatedListSchemaService against the running user, on every request.
 *
 *              Definition metadata is configuration, not business data, so it is read WITH
 *              SYSTEM_MODE. It never grants data access: every data operation runs in user mode.
 */
public with sharing class RelatedListDefinitions {
    public static final String MODE_DEFINITION = 'definition';
    public static final String MODE_LEGACY = 'legacy';
    public static final Integer MAX_COLUMNS = 25;

    private static final Pattern KEY_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,39}$');
    private static final Pattern FLOW_PATTERN = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');

    /** Test seam: Custom Metadata records cannot be inserted by tests. */
    @TestVisible
    private static Map<String, ListSpec> testDefinitions;

    /** @description Unvalidated list specification. */
    public class ListSpec {
        public String mode;
        public String definitionKey;
        public Boolean active = true;
        public String parentObject;
        public String childObject;
        public String lookupField;
        public List<ColumnSpec> columns = new List<ColumnSpec>();
        public String defaultSortField;
        public String defaultSortDirection;
        public Boolean allowCreate = false;
        public Boolean allowEdit = false;
        public Boolean allowDelete = false;
        public Boolean allowBulkDelete = false;
        public String flowApiName;
    }

    /** @description Unvalidated column specification. `key` is stable for the definition. */
    public class ColumnSpec {
        public String key;
        public String fieldPath;
        public String label;
        public Boolean visible = true;
        public Boolean searchable = false;
        public Boolean filterable = false;
        public Boolean sortable = false;
        public Boolean editable = false;
        /** Legacy only: capability flags are best-effort (unsupported types are skipped, not errors). */
        public Boolean lenient = false;

        public ColumnSpec(String key, String fieldPath) {
            this.key = key;
            this.fieldPath = fieldPath;
        }
    }

    /**
     * @description Loads an active definition by DeveloperName.
     * @param key DeveloperName of Advanced_Related_List__mdt
     * @return spec
     */
    public static ListSpec load(String key) {
        if (String.isBlank(key) || !KEY_PATTERN.matcher(key).matches()) {
            throw RelatedListException.config('The list definition key is not valid. Use the DeveloperName of an Advanced Related List definition.');
        }
        ListSpec spec = testDefinitions != null ? testDefinitions.get(key) : queryDefinition(key);
        if (spec == null) {
            throw RelatedListException.config('List definition "' + key + '" was not found. Check the List Definition Key on this page.');
        }
        if (spec.active != true) {
            throw RelatedListException.config('List definition "' + key + '" is inactive. An administrator must activate it in Setup > Custom Metadata Types.');
        }
        if (spec.columns.isEmpty()) {
            throw RelatedListException.config('List definition "' + key + '" has no columns.');
        }
        if (spec.columns.size() > MAX_COLUMNS) {
            throw RelatedListException.config('List definition "' + key + '" has more than ' + MAX_COLUMNS + ' columns.');
        }
        validateFlowName(spec.flowApiName);
        return spec;
    }

    private static ListSpec queryDefinition(String key) {
        List<Advanced_Related_List__mdt> defs = [
            SELECT
                DeveloperName,
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
            WHERE DeveloperName = :key
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (defs.isEmpty()) {
            return null;
        }
        Advanced_Related_List__mdt def = defs[0];
        ListSpec spec = new ListSpec();
        spec.mode = MODE_DEFINITION;
        spec.definitionKey = def.DeveloperName;
        spec.active = def.Active__c;
        spec.parentObject = def.Parent_Object__c;
        spec.childObject = def.Child_Object__c;
        spec.lookupField = def.Relationship_Field__c;
        spec.defaultSortField = def.Default_Sort_Field__c;
        spec.defaultSortDirection = def.Default_Sort_Direction__c;
        spec.allowCreate = def.Allow_Create__c;
        spec.allowEdit = def.Allow_Edit__c;
        spec.allowDelete = def.Allow_Delete__c;
        spec.allowBulkDelete = def.Allow_Bulk_Delete__c;
        spec.flowApiName = def.Flow_API_Name__c;

        List<Advanced_Related_List_Column__mdt> cols = [
            SELECT
                DeveloperName,
                Field_Path__c,
                Label__c,
                Order__c,
                Visible__c,
                Searchable__c,
                Filterable__c,
                Sortable__c,
                Editable__c
            FROM Advanced_Related_List_Column__mdt
            WHERE Definition__r.DeveloperName = :key
            WITH SYSTEM_MODE
        ];
        for (Advanced_Related_List_Column__mdt col : sortColumns(cols)) {
            ColumnSpec cs = new ColumnSpec(col.DeveloperName, col.Field_Path__c);
            cs.label = col.Label__c;
            cs.visible = col.Visible__c;
            cs.searchable = col.Searchable__c;
            cs.filterable = col.Filterable__c;
            cs.sortable = col.Sortable__c;
            cs.editable = col.Editable__c;
            spec.columns.add(cs);
        }
        return spec;
    }

    /** Orders by Order__c (blank last), then DeveloperName, without relying on CMT SOQL ORDER BY features. */
    private static List<Advanced_Related_List_Column__mdt> sortColumns(List<Advanced_Related_List_Column__mdt> cols) {
        List<String> sortKeys = new List<String>();
        Map<String, Advanced_Related_List_Column__mdt> byKey = new Map<String, Advanced_Related_List_Column__mdt>();
        for (Advanced_Related_List_Column__mdt col : cols) {
            Decimal ord = col.Order__c == null ? 99999 : col.Order__c;
            String sortKey = String.valueOf(ord.intValue() + 100000).leftPad(8, '0') + '|' + col.DeveloperName;
            sortKeys.add(sortKey);
            byKey.put(sortKey, col);
        }
        sortKeys.sort();
        List<Advanced_Related_List_Column__mdt> ordered = new List<Advanced_Related_List_Column__mdt>();
        for (String sortKey : sortKeys) {
            ordered.add(byKey.get(sortKey));
        }
        return ordered;
    }

    /**
     * @description Maps legacy App Builder properties to a read-oriented spec. Browser-supplied
     *              values are untrusted: they are validated exactly like a definition and can never
     *              enable bulk delete or server-side writes.
     * @param legacy legacy configuration
     * @return spec
     */
    public static ListSpec fromLegacy(RelatedListController.LegacyConfig legacy) {
        if (legacy == null || String.isBlank(legacy.childObjectApiName) || String.isBlank(legacy.parentLookupField) || String.isBlank(legacy.fieldsToDisplay)) {
            throw RelatedListException.config(
                'Set a List Definition Key, or set Child Object API Name, Parent Lookup Field API Name and Fields to Display for this component.'
            );
        }
        ListSpec spec = new ListSpec();
        spec.mode = MODE_LEGACY;
        spec.childObject = legacy.childObjectApiName.trim();
        spec.lookupField = legacy.parentLookupField.trim();
        // Platform-enforced single-record actions only (LDS / standard navigation).
        spec.allowCreate = true;
        spec.allowEdit = true;
        spec.allowDelete = true;
        spec.allowBulkDelete = false;
        spec.flowApiName = String.isBlank(legacy.flowName) ? null : legacy.flowName.trim();
        validateFlowName(spec.flowApiName);

        List<String> display = splitList(legacy.fieldsToDisplay);
        // Labels are positional: keep blanks so "Name,,Phone" labels columns 1 and 3 only.
        List<String> labels = String.isBlank(legacy.columnLabels) ? new List<String>() : legacy.columnLabels.split(',', -1);
        Set<String> searchable = lowerSet(splitList(legacy.searchableFields));
        Set<String> sortable = lowerSet(splitList(legacy.sortableFields));
        if (display.size() > MAX_COLUMNS) {
            throw RelatedListException.config('Fields to Display lists more than ' + MAX_COLUMNS + ' fields.');
        }
        Set<String> seen = new Set<String>();
        Integer index = 0;
        for (String path : display) {
            ColumnSpec cs = new ColumnSpec('c' + index, path);
            cs.label = index < labels.size() && String.isNotBlank(labels[index]) ? labels[index].trim().abbreviate(80) : null;
            cs.searchable = searchable.contains(path.toLowerCase());
            cs.sortable = sortable.contains(path.toLowerCase());
            cs.filterable = true;
            cs.lenient = true;
            spec.columns.add(cs);
            seen.add(path.toLowerCase());
            index++;
        }
        // Searchable fields that are not displayed become hidden, search-only columns (e.g. MailingStreet).
        for (String path : splitList(legacy.searchableFields)) {
            if (!seen.contains(path.toLowerCase()) && spec.columns.size() < MAX_COLUMNS) {
                ColumnSpec cs = new ColumnSpec('c' + index, path);
                cs.visible = false;
                cs.searchable = true;
                cs.lenient = true;
                spec.columns.add(cs);
                seen.add(path.toLowerCase());
                index++;
            }
        }
        spec.defaultSortField = 'CreatedDate';
        spec.defaultSortDirection = 'DESC';
        return spec;
    }

    private static void validateFlowName(String flowApiName) {
        if (String.isNotBlank(flowApiName) && !FLOW_PATTERN.matcher(flowApiName).matches()) {
            throw RelatedListException.config('The Flow API name "' + flowApiName.abbreviate(80) + '" is not valid.');
        }
    }

    @TestVisible
    private static List<String> splitList(String value) {
        List<String> result = new List<String>();
        if (String.isBlank(value)) {
            return result;
        }
        for (String part : value.split(',')) {
            if (String.isNotBlank(part)) {
                result.add(part.trim());
            }
        }
        return result;
    }

    private static Set<String> lowerSet(List<String> values) {
        Set<String> result = new Set<String>();
        for (String v : values) {
            result.add(v.toLowerCase());
        }
        return result;
    }
}
