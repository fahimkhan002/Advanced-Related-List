/**
 * @description Aura/LWC boundary for the Advanced Related List.
 *
 *              Exposed endpoints (the only ones):
 *                - getRows    : scoped, paginated read of one related list
 *                - deleteRows : bounded, scoped bulk delete (list definitions only)
 *
 *              Retired in v2 (removed, see docs/designs/ADR-001): getRecords, deleteRecord,
 *              updateRecords, getUserPermissions.
 *
 *              Responses are declared DTOs; no SObject is returned to the client. Errors are
 *              returned as a status + safe message rather than thrown, so the UI can render
 *              configuration, access and input states distinctly.
 */
public with sharing class RelatedListController {
    public static final String STATUS_OK = 'OK';
    public static final String STATUS_CONFIG = 'CONFIG_ERROR';
    public static final String STATUS_ACCESS = 'ACCESS_ERROR';
    public static final String STATUS_INPUT = 'INPUT_ERROR';
    public static final String STATUS_STALE = 'STALE_CURSOR';
    public static final String STATUS_ERROR = 'ERROR';

    @TestVisible
    private static final String GENERIC_ERROR = 'We couldn\'t complete the request. Try again, or ask your Salesforce administrator to check the list configuration.';

    // ===== REQUEST DTOs =====

    /** @description Browser-supplied legacy App Builder configuration. Untrusted input. */
    public class LegacyConfig {
        @AuraEnabled
        public String childObjectApiName { get; set; }
        @AuraEnabled
        public String parentLookupField { get; set; }
        @AuraEnabled
        public String fieldsToDisplay { get; set; }
        @AuraEnabled
        public String searchableFields { get; set; }
        @AuraEnabled
        public String sortableFields { get; set; }
        @AuraEnabled
        public String columnLabels { get; set; }
        @AuraEnabled
        public String flowName { get; set; }
    }

    /** @description One filter condition. `columnKey` refers to a column returned by the server. */
    public class FilterInput {
        @AuraEnabled
        public String columnKey { get; set; }
        @AuraEnabled
        public String operator { get; set; }
        @AuraEnabled
        public String value { get; set; }
    }

    /** @description Read request. */
    public class ListRequest {
        @AuraEnabled
        public String definitionKey { get; set; }
        @AuraEnabled
        public String parentId { get; set; }
        @AuraEnabled
        public LegacyConfig legacy { get; set; }
        @AuraEnabled
        public String searchTerm { get; set; }
        @AuraEnabled
        public List<FilterInput> filters { get; set; }
        @AuraEnabled
        public String filterLogic { get; set; }
        @AuraEnabled
        public String sortKey { get; set; }
        @AuraEnabled
        public String sortDirection { get; set; }
        @AuraEnabled
        public Integer pageSize { get; set; }
        @AuraEnabled
        public String cursor { get; set; }
    }

    /** @description Bulk delete request. */
    public class DeleteRequest {
        @AuraEnabled
        public String definitionKey { get; set; }
        @AuraEnabled
        public String parentId { get; set; }
        @AuraEnabled
        public List<String> recordIds { get; set; }
    }

    // ===== RESPONSE DTOs =====

    /** @description Column metadata the UI may render. Only usable columns are returned. */
    public class ColumnInfo {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String fieldPath;
        @AuraEnabled
        public String label;
        /** text, name, link, email, phone, url, number, currency, percent, date, datetime, boolean, picklist, address, textarea */
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Integer scale;
        @AuraEnabled
        public Boolean visible;
        @AuraEnabled
        public Boolean sortable;
        @AuraEnabled
        public Boolean filterable;
        @AuraEnabled
        public Boolean searchable;
        /** Filter value control: text, number, date, boolean, picklist */
        @AuraEnabled
        public String filterType;
        @AuraEnabled
        public List<String> operators;
        @AuraEnabled
        public List<Option> options;
    }

    /** @description Label/value pair. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** @description List-level context and capabilities for the running user. */
    public class ListContext {
        @AuraEnabled
        public String mode;
        @AuraEnabled
        public String definitionKey;
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String objectLabelPlural;
        @AuraEnabled
        public String parentObjectApiName;
        @AuraEnabled
        public String lookupField;
        @AuraEnabled
        public Boolean canCreate;
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public Boolean canDelete;
        @AuraEnabled
        public Boolean canBulkDelete;
        @AuraEnabled
        public String flowApiName;
        @AuraEnabled
        public List<String> editFields;
        @AuraEnabled
        public String sortKey;
        @AuraEnabled
        public String sortDirection;
        @AuraEnabled
        public Integer omittedColumnCount;
        @AuraEnabled
        public Integer maxDeleteBatch;
    }

    /** @description Read response. `rows` contain only `id` and declared column keys. */
    public class ListResponse {
        @AuraEnabled
        public String status = STATUS_OK;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public ListContext context;
        @AuraEnabled
        public List<ColumnInfo> columns;
        @AuraEnabled
        public List<Map<String, Object>> rows;
        /** Populated on the first page only; null when not computed. */
        @AuraEnabled
        public Integer totalCount;
        @AuraEnabled
        public Boolean totalCountCapped;
        @AuraEnabled
        public Boolean hasMore;
        @AuraEnabled
        public String nextCursor;
    }

    /** @description Per-row delete outcome. */
    public class RowResult {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String message;
        public RowResult(String recordId, Boolean success, String message) {
            this.recordId = recordId;
            this.success = success;
            this.message = message;
        }
    }

    /** @description Bulk delete response. Transaction semantics: per-row (partial success allowed). */
    public class DeleteResponse {
        @AuraEnabled
        public String status = STATUS_OK;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Integer deletedCount = 0;
        @AuraEnabled
        public Integer failedCount = 0;
        @AuraEnabled
        public List<RowResult> results = new List<RowResult>();
    }

    // ===== ENDPOINTS =====

    /**
     * @description Returns one page of a scoped related list. Not cacheable: results must reflect
     *              edits, deletes and Flow runs immediately.
     * @param request read request
     * @return page of rows with column metadata and capabilities
     */
    @AuraEnabled
    public static ListResponse getRows(ListRequest request) {
        try {
            return RelatedListService.getRows(request);
        } catch (RelatedListException e) {
            ListResponse response = new ListResponse();
            response.status = statusFor(e);
            response.message = e.getMessage();
            return response;
        } catch (Exception e) {
            ListResponse response = new ListResponse();
            response.status = STATUS_ERROR;
            response.message = GENERIC_ERROR;
            return response;
        }
    }

    /**
     * @description Deletes selected rows of a definition-backed list in one bounded request.
     * @param request delete request
     * @return per-row results
     */
    @AuraEnabled
    public static DeleteResponse deleteRows(DeleteRequest request) {
        try {
            return RelatedListService.deleteRows(request);
        } catch (RelatedListException e) {
            DeleteResponse response = new DeleteResponse();
            response.status = statusFor(e);
            response.message = e.getMessage();
            return response;
        } catch (Exception e) {
            DeleteResponse response = new DeleteResponse();
            response.status = STATUS_ERROR;
            response.message = GENERIC_ERROR;
            return response;
        }
    }

    @TestVisible
    private static String statusFor(RelatedListException e) {
        switch on e.category {
            when CONFIG {
                return STATUS_CONFIG;
            }
            when ACCESS {
                return STATUS_ACCESS;
            }
            when STALE {
                return STATUS_STALE;
            }
            when else {
                return STATUS_INPUT;
            }
        }
    }
}
