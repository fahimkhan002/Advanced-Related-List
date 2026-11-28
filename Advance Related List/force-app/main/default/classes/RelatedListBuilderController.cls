/**
 * @description Endpoints for the Tekenable Related List Builder (admin UI). Every endpoint requires the
 *              Advanced_Related_List_Admin custom permission AND the Customize Application
 *              permission. Saving writes Custom Metadata through the Apex Metadata API (asynchronous
 *              deployment); nothing here reads or writes business records.
 */
public with sharing class RelatedListBuilderController {
    // ===== DTOs =====

    /** @description Whether the running user may use the builder. */
    public class Access {
        @AuraEnabled
        public Boolean canManage = false;
        @AuraEnabled
        public String reason;
    }

    /** @description One definition in the builder's list. */
    public class DefinitionSummary {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String parentObject;
        @AuraEnabled
        public String childObject;
        @AuraEnabled
        public String lookupField;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Integer columnCount;
    }

    /** @description Editable column. `developerName` is blank for new columns. */
    public class ColumnDraft {
        @AuraEnabled
        public String developerName { get; set; }
        @AuraEnabled
        public String fieldPath { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public Boolean visible { get; set; }
        @AuraEnabled
        public Boolean searchable { get; set; }
        @AuraEnabled
        public Boolean filterable { get; set; }
        @AuraEnabled
        public Boolean sortable { get; set; }
        @AuraEnabled
        public Boolean editable { get; set; }
    }

    /** @description Editable action. `developerName` is blank for new actions. */
    public class ActionDraft {
        @AuraEnabled
        public String developerName { get; set; }
        /** Flow | Quick_Action */
        @AuraEnabled
        public String actionType { get; set; }
        @AuraEnabled
        public String target { get; set; }
        @AuraEnabled
        public String label { get; set; }
        /** List | Row */
        @AuraEnabled
        public String placement { get; set; }
        /** Header actions: Button | Menu | blank (automatic) */
        @AuraEnabled
        public String display { get; set; }
    }

    /** @description Editable definition. Column and action order is the list order. */
    public class DefinitionDraft {
        @AuraEnabled
        public String developerName { get; set; }
        @AuraEnabled
        public Boolean isNew { get; set; }
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public Boolean active { get; set; }
        @AuraEnabled
        public String parentObject { get; set; }
        @AuraEnabled
        public String childObject { get; set; }
        @AuraEnabled
        public String lookupField { get; set; }
        @AuraEnabled
        public String defaultSortField { get; set; }
        @AuraEnabled
        public String defaultSortDirection { get; set; }
        @AuraEnabled
        public Boolean allowCreate { get; set; }
        @AuraEnabled
        public Boolean allowEdit { get; set; }
        @AuraEnabled
        public Boolean allowDelete { get; set; }
        @AuraEnabled
        public Boolean allowBulkDelete { get; set; }
        @AuraEnabled
        public String flowApiName { get; set; }
        @AuraEnabled
        public List<ColumnDraft> columns { get; set; }
        @AuraEnabled
        public List<ActionDraft> actions { get; set; }
        /** Read-only: fingerprint of the saved state, used to detect when a deployment has landed. */
        @AuraEnabled
        public String signature { get; set; }
    }

    /** @description Label/value pair. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String description;
        public Option(String label, String value, String description) {
            this.label = label;
            this.value = value;
            this.description = description;
        }
    }

    /** @description A child relationship of the parent object: exactly one child object + lookup. */
    public class RelationshipOption {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String childObject;
        @AuraEnabled
        public String childLabel;
        @AuraEnabled
        public String lookupField;
        @AuraEnabled
        public String lookupLabel;
    }

    /** @description A field the admin can pick, with what the list can do with it. */
    public class FieldOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Boolean canSearch;
        @AuraEnabled
        public Boolean canFilter;
        @AuraEnabled
        public Boolean canSort;
        @AuraEnabled
        public Boolean canEdit;
        /** Set when the field is a single-target lookup the picker can drill into. */
        @AuraEnabled
        public String relationshipName;
        @AuraEnabled
        public String targetObject;
        @AuraEnabled
        public String targetLabel;
    }

    /** @description A validation finding. */
    public class Issue {
        @AuraEnabled
        public String severity;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Integer columnIndex;
        @AuraEnabled
        public Integer actionIndex;
        public Issue(String severity, String message, Integer columnIndex) {
            this.severity = severity;
            this.message = message;
            this.columnIndex = columnIndex;
        }
    }

    /** @description Validation outcome. */
    public class ValidationResult {
        @AuraEnabled
        public Boolean valid = true;
        @AuraEnabled
        public List<Issue> issues = new List<Issue>();
    }

    /** @description Save outcome. status: QUEUED | INVALID. */
    public class SaveResult {
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String jobId;
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String signature;
        @AuraEnabled
        public List<Issue> issues = new List<Issue>();
    }

    // ===== ENDPOINTS =====

    /**
     * @description Whether the running user can use the builder, with a reason when not.
     * @return access
     */
    @AuraEnabled
    public static Access getAccess() {
        return RelatedListBuilderService.access();
    }

    /**
     * @description All definitions, including inactive ones.
     * @return summaries
     */
    @AuraEnabled
    public static List<DefinitionSummary> listDefinitions() {
        guard();
        return RelatedListBuilderService.listDefinitions();
    }

    /**
     * @description One definition with its active columns in order.
     * @param developerName definition DeveloperName
     * @return draft
     */
    @AuraEnabled
    public static DefinitionDraft getDefinition(String developerName) {
        guard();
        try {
            return RelatedListBuilderService.getDefinition(developerName);
        } catch (RelatedListException e) {
            throw handled(e.getMessage());
        }
    }

    /**
     * @description Objects that can be placed on record pages (parent candidates).
     * @return options sorted by label
     */
    @AuraEnabled
    public static List<Option> listObjects() {
        guard();
        return RelatedListBuilderService.listObjects();
    }

    /**
     * @description Child relationships of a parent object (child object + lookup field pairs).
     * @param parentObject parent API name
     * @return relationships sorted by child label
     */
    @AuraEnabled
    public static List<RelationshipOption> listRelationships(String parentObject) {
        guard();
        try {
            return RelatedListBuilderService.listRelationships(parentObject);
        } catch (RelatedListException e) {
            throw handled(e.getMessage());
        }
    }

    /**
     * @description Readable fields of an object with their list capabilities.
     * @param objectApiName object API name
     * @return fields sorted by label
     */
    @AuraEnabled
    public static List<FieldOption> listFields(String objectApiName) {
        guard();
        try {
            return RelatedListBuilderService.listFields(objectApiName);
        } catch (RelatedListException e) {
            throw handled(e.getMessage());
        }
    }

    /**
     * @description Active screen flows that can be launched from the list.
     * @return options
     */
    @AuraEnabled
    public static List<Option> listFlows() {
        guard();
        return RelatedListBuilderService.listFlows();
    }

    /**
     * @description Quick actions Salesforce reports as available for an object (launchable types only).
     * @param objectApiName parent object for header buttons, child object for row items
     * @return options: label, value (action name), description (action type)
     */
    @AuraEnabled
    public static List<Option> listQuickActions(String objectApiName) {
        guard();
        try {
            return RelatedListBuilderService.listQuickActions(objectApiName);
        } catch (RelatedListException e) {
            throw handled(e.getMessage());
        }
    }

    /**
     * @description Validates a draft with the same rules the list enforces at run time.
     * @param draft draft
     * @return result
     */
    @AuraEnabled
    public static ValidationResult validateDraft(DefinitionDraft draft) {
        guard();
        return RelatedListBuilderService.validate(draft);
    }

    /**
     * @description Validates and, when valid, queues a Custom Metadata deployment.
     * @param draft draft
     * @return save result
     */
    @AuraEnabled
    public static SaveResult saveDraft(DefinitionDraft draft) {
        guard();
        try {
            return RelatedListBuilderService.save(draft);
        } catch (RelatedListException e) {
            throw handled(e.getMessage());
        }
    }

    /**
     * @description Fingerprint of the currently deployed definition (null when it does not exist).
     * @param developerName definition DeveloperName
     * @return signature
     */
    @AuraEnabled
    public static String getSignature(String developerName) {
        guard();
        return RelatedListBuilderService.currentSignature(developerName);
    }

    // ===== HELPERS =====

    private static void guard() {
        Access a = RelatedListBuilderService.access();
        if (!a.canManage) {
            throw handled(a.reason);
        }
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
