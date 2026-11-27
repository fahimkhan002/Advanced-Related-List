/**
 * @description Orchestrates scoped reads and bulk delete. Every database operation declares
 *              AccessLevel.USER_MODE (CRUD, FLS and sharing of the running user), independent of
 *              the class API version. Configuration is re-resolved and re-validated on every call.
 */
public with sharing class RelatedListService {
    public static final Integer DEFAULT_PAGE_SIZE = 10;
    public static final Integer MAX_PAGE_SIZE = 100;
    public static final Integer MAX_DELETE = 100;
    public static final String BULK_DELETE_PERMISSION = 'Advanced_Related_List_Bulk_Delete';

    @TestVisible
    private static Boolean bulkDeletePermissionOverride;

    // ===== READ =====

    /**
     * @description Returns one page of rows.
     * @param request read request
     * @return response
     */
    public static RelatedListController.ListResponse getRows(RelatedListController.ListRequest request) {
        if (request == null) {
            throw RelatedListException.input('The request is empty.');
        }
        RelatedListDefinitions.ListSpec spec = String.isNotBlank(request.definitionKey)
            ? RelatedListDefinitions.load(request.definitionKey.trim())
            : RelatedListDefinitions.fromLegacy(request.legacy);
        RelatedListSchemaService.ResolvedList rl = RelatedListSchemaService.resolve(spec, request.parentId);
        assertParentReadable(rl);

        Integer pageSize = request.pageSize == null ? DEFAULT_PAGE_SIZE : request.pageSize;
        if (pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
            throw RelatedListException.input('Records per page must be between 1 and ' + MAX_PAGE_SIZE + '.');
        }

        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(rl);
        qb.applySearch(request.searchTerm);
        qb.applyFilters(request.filters, request.filterLogic);
        qb.applySort(request.sortKey, request.sortDirection);

        RelatedListController.ListResponse response = new RelatedListController.ListResponse();
        response.context = buildContext(rl, qb);
        response.columns = buildColumns(rl);

        if (String.isBlank(request.cursor)) {
            Integer total = Database.countQueryWithBinds(qb.countQuery(), qb.getBinds(), AccessLevel.USER_MODE);
            response.totalCountCapped = total > RelatedListQueryBuilder.COUNT_CAP;
            response.totalCount = Math.min(total, RelatedListQueryBuilder.COUNT_CAP);
        } else {
            qb.applyCursor(request.cursor);
        }

        List<SObject> records = Database.queryWithBinds(qb.pageQuery(selectFields(rl, qb), pageSize), qb.getBinds(), AccessLevel.USER_MODE);
        response.hasMore = records.size() > pageSize;
        if (response.hasMore) {
            records.remove(records.size() - 1);
        }
        response.rows = new List<Map<String, Object>>();
        for (SObject record : records) {
            response.rows.add(toRow(rl, record));
        }
        if (response.hasMore && !records.isEmpty()) {
            response.nextCursor = qb.encodeCursor(records[records.size() - 1]);
        }
        return response;
    }

    private static void assertParentReadable(RelatedListSchemaService.ResolvedList rl) {
        List<SObject> parents;
        try {
            parents = Database.queryWithBinds(
                'SELECT Id FROM ' + rl.parentObject + ' WHERE Id = :parentId LIMIT 1',
                new Map<String, Object>{ 'parentId' => rl.parentId },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            parents = new List<SObject>();
        }
        if (parents.isEmpty()) {
            // Same message for "does not exist" and "no access": existence is not revealed.
            throw RelatedListException.access('This record isn\'t available to you.');
        }
    }

    private static List<String> selectFields(RelatedListSchemaService.ResolvedList rl, RelatedListQueryBuilder qb) {
        Map<String, String> fields = new Map<String, String>{ 'id' => 'Id' };
        for (RelatedListSchemaService.ResolvedColumn col : rl.columns) {
            if (!col.visible) {
                continue;
            }
            addField(fields, col.path);
            addField(fields, col.linkIdPath);
            addField(fields, col.labelPath);
            addField(fields, col.currencyPath);
        }
        if (qb.sortColumn != null) {
            addField(fields, qb.sortColumn.path);
        }
        return fields.values();
    }

    private static void addField(Map<String, String> fields, String path) {
        if (path != null && !fields.containsKey(path.toLowerCase())) {
            fields.put(path.toLowerCase(), path);
        }
    }

    private static RelatedListController.ListContext buildContext(RelatedListSchemaService.ResolvedList rl, RelatedListQueryBuilder qb) {
        Schema.DescribeSObjectResult child = rl.childDescribe;
        RelatedListDefinitions.ListSpec spec = rl.spec;
        RelatedListController.ListContext ctx = new RelatedListController.ListContext();
        ctx.mode = spec.mode;
        ctx.definitionKey = spec.definitionKey;
        ctx.objectApiName = rl.childObject;
        ctx.objectLabel = child.getLabel();
        ctx.objectLabelPlural = child.getLabelPlural();
        ctx.parentObjectApiName = rl.parentObject;
        ctx.lookupField = rl.lookupField;
        ctx.canCreate = spec.allowCreate && child.isCreateable();
        ctx.canEdit = spec.allowEdit && child.isUpdateable();
        ctx.canDelete = spec.allowDelete && child.isDeletable();
        ctx.canBulkDelete = spec.mode == RelatedListDefinitions.MODE_DEFINITION && spec.allowBulkDelete && child.isDeletable() && hasBulkDeletePermission();
        // Unchanged from v1: the Flow button is offered to users who can edit the child object.
        ctx.flowApiName = String.isNotBlank(spec.flowApiName) && child.isUpdateable() ? spec.flowApiName : null;
        ctx.editFields = new List<String>();
        for (RelatedListSchemaService.ResolvedColumn col : rl.columns) {
            if (col.editable) {
                ctx.editFields.add(col.path);
            }
        }
        ctx.sortKey = qb.sortColumn == null ? null : qb.sortColumn.key;
        ctx.sortDirection = qb.sortDirection == 'DESC' ? 'desc' : 'asc';
        ctx.omittedColumnCount = rl.omittedCount;
        ctx.maxDeleteBatch = MAX_DELETE;
        return ctx;
    }

    private static List<RelatedListController.ColumnInfo> buildColumns(RelatedListSchemaService.ResolvedList rl) {
        List<RelatedListController.ColumnInfo> result = new List<RelatedListController.ColumnInfo>();
        for (RelatedListSchemaService.ResolvedColumn col : rl.columns) {
            RelatedListController.ColumnInfo info = new RelatedListController.ColumnInfo();
            info.key = col.key;
            info.fieldPath = col.path;
            info.label = col.label;
            info.type = col.uiType;
            info.scale = col.scale;
            info.visible = col.visible;
            info.sortable = col.sortable;
            info.filterable = col.filterable;
            info.searchable = col.searchable;
            if (col.filterable) {
                info.filterType = col.filterType;
                info.operators = RelatedListQueryBuilder.OPERATORS_BY_FILTER_TYPE.get(col.filterType);
                info.options = col.picklistOptions;
            }
            result.add(info);
        }
        return result;
    }

    @TestVisible
    private static Map<String, Object> toRow(RelatedListSchemaService.ResolvedList rl, SObject record) {
        Map<String, Object> row = new Map<String, Object>{ 'id' => record.Id };
        String defaultCurrency = UserInfo.getDefaultCurrency();
        for (RelatedListSchemaService.ResolvedColumn col : rl.columns) {
            if (!col.visible) {
                continue;
            }
            Object value = displayValue(col, readPath(record, col.path));
            if (col.labelPath != null) {
                Object label = readPath(record, col.labelPath);
                if (label != null) {
                    value = label;
                }
            }
            if (value == null) {
                continue; // absent key == blank; false and 0 are kept
            }
            row.put(col.key, value);
            if (col.linkIdPath != null) {
                Object linkId = readPath(record, col.linkIdPath);
                if (linkId != null) {
                    row.put(col.key + '__id', String.valueOf(linkId));
                }
            }
            if (col.displayType == Schema.DisplayType.CURRENCY) {
                Object code = col.currencyPath == null ? defaultCurrency : readPath(record, col.currencyPath);
                row.put(col.key + '__cur', code == null ? defaultCurrency : code);
            }
        }
        return row;
    }

    private static Object displayValue(RelatedListSchemaService.ResolvedColumn col, Object raw) {
        if (raw == null) {
            return null;
        }
        Schema.DisplayType t = col.displayType;
        if (t == Schema.DisplayType.PICKLIST) {
            String label = col.picklistLabels.get(String.valueOf(raw));
            return label == null ? raw : label;
        }
        if (t == Schema.DisplayType.MULTIPICKLIST) {
            List<String> labels = new List<String>();
            for (String part : String.valueOf(raw).split(';')) {
                String label = col.picklistLabels.get(part);
                labels.add(label == null ? part : label);
            }
            return String.join(labels, '; ');
        }
        if (t == Schema.DisplayType.ADDRESS) {
            return formatAddress((System.Address) raw);
        }
        if (t == Schema.DisplayType.LOCATION) {
            System.Location loc = (System.Location) raw;
            return loc.getLatitude() + ', ' + loc.getLongitude();
        }
        if (t == Schema.DisplayType.TIME) {
            Time tm = (Time) raw;
            return String.valueOf(tm.hour()).leftPad(2, '0') + ':' + String.valueOf(tm.minute()).leftPad(2, '0');
        }
        if (t == Schema.DisplayType.TEXTAREA && raw instanceof String) {
            String text = (String) raw;
            return text.contains('<') ? text.stripHtmlTags() : text;
        }
        return raw;
    }

    @TestVisible
    private static String formatAddress(System.Address address) {
        List<String> parts = new List<String>();
        addPart(parts, address.getStreet());
        String locality = String.join(nonBlank(new List<String>{ address.getCity(), address.getState() }), ', ');
        if (String.isNotBlank(address.getPostalCode())) {
            locality = String.isBlank(locality) ? address.getPostalCode() : locality + ' ' + address.getPostalCode();
        }
        addPart(parts, locality);
        addPart(parts, address.getCountry());
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static List<String> nonBlank(List<String> values) {
        List<String> result = new List<String>();
        for (String v : values) {
            addPart(result, v);
        }
        return result;
    }

    private static void addPart(List<String> parts, String value) {
        if (String.isNotBlank(value)) {
            parts.add(value.trim());
        }
    }

    /**
     * @description Reads a canonical relationship path ("Account.Owner.Name") from a queried record.
     * @param record queried record
     * @param path canonical path
     * @return value or null
     */
    public static Object readPath(SObject record, String path) {
        List<String> segments = path.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < segments.size() - 1; i++) {
            current = current.getSObject(segments[i]);
            if (current == null) {
                return null;
            }
        }
        return current.get(segments[segments.size() - 1]);
    }

    // ===== BULK DELETE =====

    /**
     * @description Deletes up to MAX_DELETE rows of a definition-backed list. Rows are re-queried
     *              in user mode within the list's parent scope immediately before the delete.
     *              Semantics: per-row (partial success). Rows outside the scope or not visible
     *              are reported as unavailable without revealing whether they exist.
     * @param request delete request
     * @return per-row results
     */
    public static RelatedListController.DeleteResponse deleteRows(RelatedListController.DeleteRequest request) {
        if (request == null || String.isBlank(request.definitionKey)) {
            throw RelatedListException.config('Deleting several records requires a list definition. Ask your administrator to migrate this list.');
        }
        RelatedListDefinitions.ListSpec spec = RelatedListDefinitions.load(request.definitionKey.trim());
        RelatedListSchemaService.ResolvedList rl = RelatedListSchemaService.resolve(spec, request.parentId);
        if (!(spec.allowBulkDelete && rl.childDescribe.isDeletable() && hasBulkDeletePermission())) {
            throw RelatedListException.access('You don\'t have permission to delete several records from this list.');
        }
        assertParentReadable(rl);

        List<String> rawIds = request.recordIds == null ? new List<String>() : request.recordIds;
        if (rawIds.isEmpty()) {
            throw RelatedListException.input('Select at least one record to delete.');
        }
        if (rawIds.size() > MAX_DELETE) {
            throw RelatedListException.input('You can delete up to ' + MAX_DELETE + ' records at a time.');
        }

        RelatedListController.DeleteResponse response = new RelatedListController.DeleteResponse();
        Schema.SObjectType childType = rl.childDescribe.getSObjectType();
        Set<Id> candidateIds = new Set<Id>();
        List<String> orderedKeys = new List<String>();
        for (String raw : rawIds) {
            Id parsed = toIdOrNull(raw);
            if (parsed == null || parsed.getSObjectType() != childType) {
                response.results.add(new RelatedListController.RowResult(raw == null ? null : raw.abbreviate(18), false, 'This record isn\'t available.'));
                continue;
            }
            if (!candidateIds.contains(parsed)) {
                candidateIds.add(parsed);
                orderedKeys.add(parsed);
            }
        }

        Map<Id, SObject> inScope = new Map<Id, SObject>();
        if (!candidateIds.isEmpty()) {
            inScope = new Map<Id, SObject>(
                Database.queryWithBinds(
                    'SELECT Id FROM ' + rl.childObject + ' WHERE Id IN :ids AND ' + rl.lookupField + ' = :parentId',
                    new Map<String, Object>{ 'ids' => candidateIds, 'parentId' => rl.parentId },
                    AccessLevel.USER_MODE
                )
            );
        }

        List<SObject> toDelete = new List<SObject>();
        for (String key : orderedKeys) {
            Id recordId = Id.valueOf(key);
            if (inScope.containsKey(recordId)) {
                toDelete.add(inScope.get(recordId));
            } else {
                response.results.add(new RelatedListController.RowResult(key, false, 'This record isn\'t available.'));
            }
        }

        if (!toDelete.isEmpty()) {
            List<Database.DeleteResult> results = Database.delete(toDelete, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                Database.DeleteResult result = results[i];
                String recordId = toDelete[i].Id;
                if (result.isSuccess()) {
                    response.results.add(new RelatedListController.RowResult(recordId, true, null));
                } else {
                    response.results.add(new RelatedListController.RowResult(recordId, false, firstError(result)));
                }
            }
        }
        for (RelatedListController.RowResult rr : response.results) {
            if (rr.success) {
                response.deletedCount++;
            } else {
                response.failedCount++;
            }
        }
        return response;
    }

    private static String firstError(Database.DeleteResult result) {
        List<Database.Error> errors = result.getErrors();
        if (errors.isEmpty() || String.isBlank(errors[0].getMessage())) {
            return 'The record couldn\'t be deleted.';
        }
        return errors[0].getMessage().abbreviate(255);
    }

    private static Id toIdOrNull(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return Id.valueOf(raw.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean hasBulkDeletePermission() {
        if (Test.isRunningTest() && bulkDeletePermissionOverride != null) {
            return bulkDeletePermissionOverride;
        }
        return FeatureManagement.checkPermission(BULK_DELETE_PERMISSION);
    }
}
