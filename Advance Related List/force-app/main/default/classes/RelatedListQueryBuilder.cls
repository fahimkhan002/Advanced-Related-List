/**
 * @description Single predicate builder for the list query and its count query.
 *              - Identifiers come only from RelatedListSchemaService (canonical describe names).
 *              - Operators and joins come only from fixed maps; every value is a bind variable.
 *              - Values are parsed by Salesforce field type; LIKE wildcards typed by users are literal.
 *              - Ordering is `<sort> NULLS LAST, Id ASC` with a keyset cursor bound to a fingerprint
 *                of the query, so pages never skip or repeat rows when sort values repeat.
 */
public with sharing class RelatedListQueryBuilder {
    public static final Integer MAX_FILTERS = 20;
    public static final Integer MAX_SEARCH_LENGTH = 100;
    public static final Integer MAX_VALUE_LENGTH = 255;
    public static final Integer COUNT_CAP = 2000;

    public static final Map<String, List<String>> OPERATORS_BY_FILTER_TYPE = new Map<String, List<String>>{
        'text' => new List<String>{ 'equals', 'notEquals', 'contains', 'notContains', 'startsWith', 'endsWith', 'isBlank', 'isNotBlank' },
        'picklist' => new List<String>{ 'equals', 'notEquals', 'isBlank', 'isNotBlank' },
        'number' => new List<String>{ 'equals', 'notEquals', 'lessThan', 'greaterThan', 'lessOrEqual', 'greaterOrEqual', 'isBlank', 'isNotBlank' },
        'date' => new List<String>{ 'equals', 'notEquals', 'lessThan', 'greaterThan', 'lessOrEqual', 'greaterOrEqual', 'isBlank', 'isNotBlank' },
        'boolean' => new List<String>{ 'equals' }
    };
    private static final Map<String, String> COMPARISON = new Map<String, String>{
        'equals' => '=',
        'notEquals' => '!=',
        'lessThan' => '<',
        'greaterThan' => '>',
        'lessOrEqual' => '<=',
        'greaterOrEqual' => '>='
    };

    private final RelatedListSchemaService.ResolvedList rl;
    private final Map<String, Object> binds = new Map<String, Object>();
    private final List<String> scope = new List<String>();
    private final List<String> fingerprintParts = new List<String>();
    private String keyset;
    private Integer bindIndex = 0;

    public RelatedListSchemaService.ResolvedColumn sortColumn;
    public String sortDirection = 'ASC';

    /**
     * @description Starts with the mandatory parent scope predicate.
     * @param rl resolved list
     */
    public RelatedListQueryBuilder(RelatedListSchemaService.ResolvedList rl) {
        this.rl = rl;
        scope.add(rl.lookupField + ' = ' + bind(rl.parentId));
        fingerprintParts.add(rl.spec.mode);
        fingerprintParts.add(String.valueOf(rl.spec.definitionKey));
        fingerprintParts.add(rl.childObject);
        fingerprintParts.add(rl.lookupField);
        fingerprintParts.add(String.valueOf(rl.parentId));
        fingerprintParts.add(UserInfo.getUserId());
        this.sortColumn = rl.defaultSort;
        this.sortDirection = rl.defaultDirection;
    }

    // ===== SEARCH =====

    /**
     * @description Adds an OR-joined LIKE across searchable columns. `%`, `_` and `\` are literal.
     * @param term user search text
     */
    public void applySearch(String term) {
        String trimmed = term == null ? '' : term.trim();
        fingerprintParts.add('s:' + trimmed.toLowerCase());
        if (trimmed.length() == 0) {
            return;
        }
        if (trimmed.length() > MAX_SEARCH_LENGTH) {
            throw RelatedListException.input('Search text can be up to ' + MAX_SEARCH_LENGTH + ' characters.');
        }
        List<String> parts = new List<String>();
        String placeholder = null;
        for (RelatedListSchemaService.ResolvedColumn col : rl.columns) {
            if (col.searchable) {
                if (placeholder == null) {
                    placeholder = bind('%' + escapeLike(trimmed) + '%');
                }
                parts.add(col.path + ' LIKE ' + placeholder);
            }
        }
        if (!parts.isEmpty()) {
            scope.add('(' + String.join(parts, ' OR ') + ')');
        }
    }

    // ===== FILTERS =====

    /**
     * @description Adds typed filter conditions joined by AND (default) or OR.
     * @param filters filter inputs referencing column keys
     * @param logic AND | OR
     */
    public void applyFilters(List<RelatedListController.FilterInput> filters, String logic) {
        if (filters == null || filters.isEmpty()) {
            fingerprintParts.add('f:none');
            return;
        }
        if (filters.size() > MAX_FILTERS) {
            throw RelatedListException.input('Use up to ' + MAX_FILTERS + ' filters.');
        }
        String join = 'OR'.equalsIgnoreCase(logic) ? ' OR ' : ' AND ';
        List<String> conditions = new List<String>();
        for (RelatedListController.FilterInput filter : filters) {
            if (filter == null) {
                throw RelatedListException.input('A filter is incomplete.');
            }
            conditions.add(condition(filter));
            fingerprintParts.add('f:' + filter.columnKey + ':' + filter.operator + ':' + filter.value);
        }
        fingerprintParts.add('j:' + join.trim());
        scope.add('(' + String.join(conditions, join) + ')');
    }

    private String condition(RelatedListController.FilterInput filter) {
        RelatedListSchemaService.ResolvedColumn col = filter.columnKey == null ? null : rl.byKey.get(filter.columnKey);
        if (col == null || !col.filterable) {
            throw RelatedListException.input('One of the filters uses a field that can\'t be filtered.');
        }
        List<String> allowed = OPERATORS_BY_FILTER_TYPE.get(col.filterType);
        if (filter.operator == null || allowed == null || !allowed.contains(filter.operator)) {
            throw RelatedListException.input('The filter operator for "' + col.label + '" is not supported.');
        }
        String op = filter.operator;
        String path = col.path;
        if (op == 'isBlank') {
            return path + ' = null';
        }
        if (op == 'isNotBlank') {
            return path + ' != null';
        }
        String raw = filter.value == null ? '' : filter.value.trim();
        if (raw.length() == 0) {
            throw RelatedListException.input('Enter a value for the "' + col.label + '" filter.');
        }
        if (raw.length() > MAX_VALUE_LENGTH) {
            throw RelatedListException.input('The "' + col.label + '" filter value is too long.');
        }
        switch on col.filterType {
            when 'text' {
                return textCondition(path, op, raw);
            }
            when 'picklist' {
                if (col.picklistLabels == null || !col.picklistLabels.containsKey(raw)) {
                    throw RelatedListException.input('Choose a valid value for the "' + col.label + '" filter.');
                }
                return path + ' ' + COMPARISON.get(op) + ' ' + bind(raw);
            }
            when 'number' {
                return path + ' ' + COMPARISON.get(op) + ' ' + bind(parseDecimal(raw, col.label));
            }
            when 'date' {
                Date day = parseDate(raw, col.label);
                if (col.displayType == Schema.DisplayType.DATETIME) {
                    return datetimeCondition(path, op, day);
                }
                return path + ' ' + COMPARISON.get(op) + ' ' + bind(day);
            }
            when else {
                // boolean
                if (raw != 'true' && raw != 'false') {
                    throw RelatedListException.input('Choose True or False for the "' + col.label + '" filter.');
                }
                return path + ' = ' + bind(raw == 'true');
            }
        }
    }

    private String textCondition(String path, String op, String raw) {
        String escaped = escapeLike(raw);
        switch on op {
            when 'contains' {
                return path + ' LIKE ' + bind('%' + escaped + '%');
            }
            when 'notContains' {
                return '(' + path + ' = null OR (NOT ' + path + ' LIKE ' + bind('%' + escaped + '%') + '))';
            }
            when 'startsWith' {
                return path + ' LIKE ' + bind(escaped + '%');
            }
            when 'endsWith' {
                return path + ' LIKE ' + bind('%' + escaped);
            }
            when 'notEquals' {
                return path + ' != ' + bind(raw);
            }
            when else {
                return path + ' = ' + bind(raw);
            }
        }
    }

    /** A date entered for a date/time field means the whole day in the user's time zone. */
    private String datetimeCondition(String path, String op, Date day) {
        Datetime startOfDay = Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
        Datetime nextDay = startOfDay.addDays(1);
        switch on op {
            when 'equals' {
                return '(' + path + ' >= ' + bind(startOfDay) + ' AND ' + path + ' < ' + bind(nextDay) + ')';
            }
            when 'notEquals' {
                return '(' + path + ' < ' + bind(startOfDay) + ' OR ' + path + ' >= ' + bind(nextDay) + ')';
            }
            when 'lessThan' {
                return path + ' < ' + bind(startOfDay);
            }
            when 'greaterThan' {
                return path + ' >= ' + bind(nextDay);
            }
            when 'lessOrEqual' {
                return path + ' < ' + bind(nextDay);
            }
            when else {
                return path + ' >= ' + bind(startOfDay);
            }
        }
    }

    // ===== SORT =====

    /**
     * @description Applies a requested sort; unknown or non-sortable keys fall back to the default.
     * @param sortKey column key
     * @param direction asc | desc
     */
    public void applySort(String sortKey, String direction) {
        if (String.isNotBlank(sortKey)) {
            RelatedListSchemaService.ResolvedColumn col = rl.byKey.get(sortKey);
            if (col == null || !col.sortable) {
                throw RelatedListException.input('This column can\'t be sorted.');
            }
            sortColumn = col;
            sortDirection = 'desc'.equalsIgnoreCase(direction) ? 'DESC' : 'ASC';
        }
        fingerprintParts.add('o:' + (sortColumn == null ? 'Id' : sortColumn.path) + ':' + sortDirection);
    }

    /**
     * @description ORDER BY clause with a unique tie-breaker and defined null placement.
     * @return order by clause (without the keywords)
     */
    public String orderBy() {
        if (sortColumn == null) {
            return 'Id ASC';
        }
        return sortColumn.path + ' ' + sortDirection + ' NULLS LAST, Id ASC';
    }

    // ===== CURSOR =====

    /**
     * @description Hash of everything that defines the result set; cursors are only valid for it.
     * @return fingerprint
     */
    public String fingerprint() {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(fingerprintParts, '|')));
        return EncodingUtil.convertToHex(digest).left(32);
    }

    /**
     * @description Applies a keyset cursor. Any mismatch or tampering yields a STALE error.
     * @param token cursor from a previous response
     */
    public void applyCursor(String token) {
        if (String.isBlank(token)) {
            return;
        }
        Map<String, Object> cursor;
        try {
            cursor = (Map<String, Object>) JSON.deserializeUntyped(EncodingUtil.base64Decode(token).toString());
        } catch (Exception e) {
            throw RelatedListException.stale();
        }
        if (cursor == null || cursor.get('f') != fingerprint()) {
            throw RelatedListException.stale();
        }
        Id lastId;
        try {
            lastId = Id.valueOf(String.valueOf(cursor.get('i')));
        } catch (Exception e) {
            throw RelatedListException.stale();
        }
        if (lastId.getSObjectType() != rl.childDescribe.getSObjectType()) {
            throw RelatedListException.stale();
        }
        String idBind = bind(lastId);
        if (sortColumn == null) {
            keyset = 'Id > ' + idBind;
            return;
        }
        String path = sortColumn.path;
        if (cursor.get('n') == true) {
            keyset = '(' + path + ' = null AND Id > ' + idBind + ')';
            return;
        }
        String valueBind = bind(decodeValue(cursor.get('v')));
        String comparator = sortDirection == 'DESC' ? ' < ' : ' > ';
        keyset = '(' + path + comparator + valueBind + ' OR (' + path + ' = ' + valueBind + ' AND Id > ' + idBind + ') OR ' + path + ' = null)';
    }

    /**
     * @description Builds the cursor that continues after the given row.
     * @param lastRow last row of the current page (must include the sort path)
     * @return opaque cursor
     */
    public String encodeCursor(SObject lastRow) {
        Map<String, Object> cursor = new Map<String, Object>{ 'f' => fingerprint(), 'i' => lastRow.Id };
        if (sortColumn != null) {
            Object value = RelatedListService.readPath(lastRow, sortColumn.path);
            cursor.put('n', value == null);
            if (value != null) {
                cursor.put('v', value);
            }
        }
        return EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(cursor)));
    }

    private Object decodeValue(Object raw) {
        try {
            String text = String.valueOf(raw);
            Schema.DisplayType t = sortColumn.displayType;
            if (t == Schema.DisplayType.DATE) {
                return Date.valueOf(text);
            }
            if (t == Schema.DisplayType.DATETIME) {
                return (Datetime) JSON.deserialize(JSON.serialize(text), Datetime.class);
            }
            if (t == Schema.DisplayType.INTEGER) {
                return Integer.valueOf(text);
            }
            if (t == Schema.DisplayType.LONG) {
                return Long.valueOf(text);
            }
            if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) {
                return Decimal.valueOf(text);
            }
            return text;
        } catch (Exception e) {
            throw RelatedListException.stale();
        }
    }

    // ===== QUERIES =====

    /**
     * @description Count query over the same scope as the list (no keyset), capped.
     * @return SOQL
     */
    public String countQuery() {
        return 'SELECT COUNT() FROM ' + rl.childObject + ' WHERE ' + String.join(scope, ' AND ') + ' LIMIT ' + (COUNT_CAP + 1);
    }

    /**
     * @description Page query: same scope plus keyset, stable order, one extra row to detect more.
     * @param selectFields canonical field paths
     * @param pageSize validated page size
     * @return SOQL
     */
    public String pageQuery(List<String> selectFields, Integer pageSize) {
        List<String> conditions = new List<String>(scope);
        if (keyset != null) {
            conditions.add(keyset);
        }
        return 'SELECT ' + String.join(selectFields, ', ') + ' FROM ' + rl.childObject + ' WHERE ' + String.join(conditions, ' AND ') + ' ORDER BY ' + orderBy() + ' LIMIT ' + (pageSize + 1);
    }

    /**
     * @description Bind map for queryWithBinds / countQueryWithBinds.
     * @return binds
     */
    public Map<String, Object> getBinds() {
        return binds;
    }

    // ===== HELPERS =====

    private String bind(Object value) {
        String name = 'arl' + bindIndex++;
        binds.put(name, value);
        return ':' + name;
    }

    /**
     * @description Escapes LIKE metacharacters so user input is matched literally.
     * @param value raw text
     * @return escaped text
     */
    public static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static Decimal parseDecimal(String raw, String label) {
        try {
            return Decimal.valueOf(raw);
        } catch (Exception e) {
            throw RelatedListException.input('Enter a valid number for the "' + label + '" filter.');
        }
    }

    private static Date parseDate(String raw, String label) {
        try {
            return Date.valueOf(raw);
        } catch (Exception e) {
            throw RelatedListException.input('Enter a valid date for the "' + label + '" filter.');
        }
    }
}
