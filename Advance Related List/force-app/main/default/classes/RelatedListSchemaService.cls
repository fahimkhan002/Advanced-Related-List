/**
 * @description Validates a ListSpec against the schema and the running user's permissions.
 *              Produces a ResolvedList whose identifiers are canonical describe names; only these
 *              identifiers are ever concatenated into SOQL. Describe results are cached per
 *              transaction.
 */
public with sharing class RelatedListSchemaService {
    public static final Integer MAX_HOPS = 5;
    private static final Pattern IDENTIFIER = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');

    private static final Set<Schema.DisplayType> SEARCH_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.PICKLIST
    };
    private static final Set<Schema.DisplayType> SORT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG
    };

    private static Map<String, Schema.DescribeSObjectResult> objectCache = new Map<String, Schema.DescribeSObjectResult>();
    private static Map<String, Map<String, Schema.SObjectField>> fieldCache = new Map<String, Map<String, Schema.SObjectField>>();
    private static Map<String, String> nameFieldCache = new Map<String, String>();

    /** @description Validated list, ready for query building. */
    public class ResolvedList {
        public RelatedListDefinitions.ListSpec spec;
        public Schema.DescribeSObjectResult childDescribe;
        public String childObject;
        public String parentObject;
        public Id parentId;
        public Schema.SObjectType parentType;
        public String lookupField;
        public List<ResolvedColumn> columns = new List<ResolvedColumn>();
        public Map<String, ResolvedColumn> byKey = new Map<String, ResolvedColumn>();
        public Integer omittedCount = 0;
        /** Null means order by Id only. */
        public ResolvedColumn defaultSort;
        public String defaultDirection = 'ASC';
    }

    /** @description Validated column. */
    public class ResolvedColumn {
        public String key;
        public String path;
        public String label;
        public Schema.DisplayType displayType;
        public String uiType;
        public Integer scale;
        public Boolean visible = true;
        public Boolean searchable = false;
        public Boolean filterable = false;
        public Boolean sortable = false;
        public Boolean editable = false;
        public Boolean compound = false;
        public String filterType;
        public String linkIdPath;
        public String labelPath;
        public String currencyPath;
        public Map<String, String> picklistLabels;
        public List<RelatedListController.Option> picklistOptions;
    }

    /** @description Result of resolving a field path. */
    public class FieldPath {
        public String path;
        public String prefix = '';
        public Integer depth = 0;
        public Boolean accessible = true;
        public Schema.DescribeFieldResult field;
        public String ownerObject;
    }

    // ===== ENTRY POINT =====

    /**
     * @description Validates spec + parent id for the running user.
     * @param spec unvalidated spec
     * @param parentIdValue parent record id from the page
     * @return resolved list
     */
    public static ResolvedList resolve(RelatedListDefinitions.ListSpec spec, String parentIdValue) {
        Id parentId = parseParentId(parentIdValue);
        ResolvedList rl = resolveForParentType(spec, parentId.getSObjectType());
        rl.parentId = parentId;
        return rl;
    }

    /**
     * @description Validates a spec for a parent object type without a record (used by the admin
     *              builder). Applies exactly the same rules as the runtime path for the running user.
     * @param spec unvalidated spec
     * @param parentType parent object type
     * @return resolved list (parentId is null)
     */
    public static ResolvedList resolveForParentType(RelatedListDefinitions.ListSpec spec, Schema.SObjectType parentType) {
        ResolvedList rl = new ResolvedList();
        rl.spec = spec;
        rl.parentType = parentType;

        rl.childDescribe = describeObject(spec.childObject, 'Child object');
        rl.childObject = rl.childDescribe.getName();
        if (!rl.childDescribe.isAccessible()) {
            throw RelatedListException.access('You don\'t have access to ' + rl.childDescribe.getLabelPlural() + '.');
        }
        rl.parentObject = parentType.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (spec.mode == RelatedListDefinitions.MODE_DEFINITION) {
            Schema.DescribeSObjectResult configuredParent = describeObject(spec.parentObject, 'Parent object');
            if (configuredParent.getName() != rl.parentObject) {
                throw RelatedListException.config(
                    'List definition "' + spec.definitionKey + '" is for ' + configuredParent.getName() + ' records, but this page shows ' + rl.parentObject + ' records.'
                );
            }
        }
        rl.lookupField = resolveLookup(rl, spec.lookupField);

        for (RelatedListDefinitions.ColumnSpec cs : spec.columns) {
            ResolvedColumn col = resolveColumn(rl, cs);
            if (col != null) {
                rl.columns.add(col);
                rl.byKey.put(col.key, col);
            }
        }
        if (visibleCount(rl) == 0) {
            throw RelatedListException.access('You don\'t have access to any of the fields in this list.');
        }
        resolveDefaultSort(rl);
        return rl;
    }

    private static Id parseParentId(String value) {
        if (String.isBlank(value)) {
            throw RelatedListException.config('Place this component on a record page so it can show related records.');
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            throw RelatedListException.input('The parent record ID is not valid.');
        }
    }

    private static String resolveLookup(ResolvedList rl, String lookupName) {
        if (String.isBlank(lookupName) || !IDENTIFIER.matcher(lookupName).matches()) {
            throw RelatedListException.config('The parent lookup field is missing or not valid.');
        }
        Schema.SObjectField field = fieldsOf(rl.childDescribe).get(lookupName.toLowerCase());
        if (field == null) {
            throw RelatedListException.config('Field "' + lookupName + '" was not found on ' + rl.childObject + '.');
        }
        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (dfr.getType() != Schema.DisplayType.REFERENCE) {
            throw RelatedListException.config('Field "' + dfr.getName() + '" on ' + rl.childObject + ' is not a lookup field.');
        }
        Boolean targetsParent = false;
        for (Schema.SObjectType target : dfr.getReferenceTo()) {
            if (target == rl.parentType) {
                targetsParent = true;
            }
        }
        if (!targetsParent) {
            throw RelatedListException.config('Lookup "' + dfr.getName() + '" on ' + rl.childObject + ' does not point to ' + rl.parentObject + '.');
        }
        if (!dfr.isAccessible()) {
            throw RelatedListException.access('You don\'t have access to the field that links these records.');
        }
        if (!dfr.isFilterable()) {
            throw RelatedListException.config('Lookup "' + dfr.getName() + '" cannot be used to filter records.');
        }
        return dfr.getName();
    }

    // ===== COLUMNS =====

    private static ResolvedColumn resolveColumn(ResolvedList rl, RelatedListDefinitions.ColumnSpec cs) {
        FieldPath fp = resolvePath(rl.childDescribe, cs.fieldPath);
        if (!fp.accessible) {
            if (cs.visible) {
                rl.omittedCount++;
            }
            return null;
        }
        Schema.DescribeFieldResult dfr = fp.field;
        ResolvedColumn col = new ResolvedColumn();
        col.key = cs.key;
        col.path = fp.path;
        col.visible = cs.visible;
        col.displayType = dfr.getType();
        col.label = String.isNotBlank(cs.label) ? cs.label : labelFor(fp);
        col.scale = dfr.getScale();
        col.compound = col.displayType == Schema.DisplayType.ADDRESS || col.displayType == Schema.DisplayType.LOCATION;
        if (col.compound && fp.depth > 0) {
            throw RelatedListException.config('Compound field "' + cs.fieldPath + '" is only supported directly on ' + rl.childObject + '.');
        }
        if (col.displayType == Schema.DisplayType.BASE64) {
            throw RelatedListException.config('Field "' + cs.fieldPath + '" has a type that cannot be displayed.');
        }
        col.uiType = uiTypeFor(col.displayType);
        col.filterType = filterTypeFor(col.displayType);

        if (dfr.isNameField()) {
            col.uiType = 'name';
            col.linkIdPath = fp.prefix + 'Id';
        } else if (col.displayType == Schema.DisplayType.REFERENCE) {
            col.uiType = 'link';
            col.linkIdPath = fp.path;
            col.labelPath = referenceLabelPath(fp);
            col.filterType = null;
        }
        if (col.displayType == Schema.DisplayType.CURRENCY && UserInfo.isMultiCurrencyOrganization()) {
            col.currencyPath = fp.prefix + 'CurrencyIsoCode';
        }
        if (col.displayType == Schema.DisplayType.PICKLIST || col.displayType == Schema.DisplayType.MULTIPICKLIST) {
            col.picklistLabels = new Map<String, String>();
            col.picklistOptions = new List<RelatedListController.Option>();
            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                col.picklistLabels.put(entry.getValue(), entry.getLabel());
                if (entry.isActive()) {
                    col.picklistOptions.add(new RelatedListController.Option(entry.getLabel(), entry.getValue()));
                }
            }
        }

        col.searchable = capability(cs.searchable, supportsSearch(dfr), cs, 'searched');
        col.filterable = capability(cs.filterable, supportsFilter(dfr), cs, 'filtered');
        col.sortable = capability(cs.sortable, supportsSort(dfr), cs, 'sorted');
        if (cs.editable == true) {
            if (fp.depth > 0) {
                throw RelatedListException.config('Field "' + cs.fieldPath + '" belongs to a related record and cannot be edited from this list.');
            }
            // Per-user permission: silently not editable for users without edit access to the field.
            col.editable = dfr.isUpdateable();
        }
        return col;
    }

    // ===== CAPABILITY RULES (shared by runtime and the admin builder) =====

    private static Boolean isCompound(Schema.DescribeFieldResult dfr) {
        return dfr.getType() == Schema.DisplayType.ADDRESS || dfr.getType() == Schema.DisplayType.LOCATION;
    }

    /**
     * @description Whether a field can be used in the search box.
     * @param dfr field describe
     * @return true when supported
     */
    public static Boolean supportsSearch(Schema.DescribeFieldResult dfr) {
        return dfr.isFilterable() && !isCompound(dfr) && SEARCH_TYPES.contains(dfr.getType());
    }

    /**
     * @description Whether a field can be offered in the filter panel.
     * @param dfr field describe
     * @return true when supported
     */
    public static Boolean supportsFilter(Schema.DescribeFieldResult dfr) {
        return dfr.isFilterable() && !isCompound(dfr) && dfr.getType() != Schema.DisplayType.REFERENCE && filterTypeFor(dfr.getType()) != null;
    }

    /**
     * @description Whether the whole list can be sorted by a field.
     * @param dfr field describe
     * @return true when supported
     */
    public static Boolean supportsSort(Schema.DescribeFieldResult dfr) {
        return dfr.isFilterable() && dfr.isSortable() && !isCompound(dfr) && SORT_TYPES.contains(dfr.getType());
    }

    private static Boolean capability(Boolean requested, Boolean supported, RelatedListDefinitions.ColumnSpec cs, String verb) {
        if (requested != true) {
            return false;
        }
        if (supported) {
            return true;
        }
        if (cs.lenient) {
            return false;
        }
        throw RelatedListException.config('Field "' + cs.fieldPath + '" cannot be ' + verb + '. Update the column in the list definition.');
    }

    private static void resolveDefaultSort(ResolvedList rl) {
        String sortField = rl.spec.defaultSortField;
        rl.defaultDirection = 'DESC'.equalsIgnoreCase(rl.spec.defaultSortDirection) ? 'DESC' : 'ASC';
        if (String.isBlank(sortField)) {
            return;
        }
        for (ResolvedColumn col : rl.columns) {
            if (col.path.equalsIgnoreCase(sortField) && col.sortable) {
                rl.defaultSort = col;
                return;
            }
        }
        Boolean legacy = rl.spec.mode == RelatedListDefinitions.MODE_LEGACY;
        if (legacy && !fieldsOf(rl.childDescribe).containsKey(sortField.toLowerCase())) {
            return; // legacy default (CreatedDate) absent: order by Id
        }
        FieldPath fp = resolvePath(rl.childDescribe, sortField);
        if (!fp.accessible) {
            return; // user cannot read the default sort field: deterministic Id order instead
        }
        Schema.DescribeFieldResult dfr = fp.field;
        if (!supportsSort(dfr)) {
            if (legacy) {
                return;
            }
            throw RelatedListException.config('Default sort field "' + sortField + '" cannot be sorted.');
        }
        ResolvedColumn hidden = new ResolvedColumn();
        hidden.key = '_sort';
        hidden.path = fp.path;
        hidden.label = dfr.getLabel();
        hidden.visible = false;
        hidden.sortable = true;
        hidden.displayType = dfr.getType();
        rl.defaultSort = hidden;
    }

    // ===== FIELD PATHS =====

    /**
     * @description Resolves "Rel1.Rel2.Field" hop by hop, checking every relationship and the
     *              terminal field for read access. Unknown names are configuration errors.
     * @param root describe of the starting object
     * @param rawPath configured path
     * @return resolved path (accessible=false when any hop or the field is not readable)
     */
    public static FieldPath resolvePath(Schema.DescribeSObjectResult root, String rawPath) {
        if (String.isBlank(rawPath)) {
            throw RelatedListException.config('A column has no field.');
        }
        List<String> segments = rawPath.trim().split('\\.');
        if (segments.size() > MAX_HOPS + 1) {
            throw RelatedListException.config('Field "' + rawPath + '" has more than ' + MAX_HOPS + ' relationship hops.');
        }
        FieldPath fp = new FieldPath();
        fp.depth = segments.size() - 1;
        Schema.DescribeSObjectResult current = root;
        List<String> canonical = new List<String>();
        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];
            if (!IDENTIFIER.matcher(segment).matches()) {
                throw RelatedListException.config('Field "' + rawPath.abbreviate(120) + '" is not a valid field path.');
            }
            Boolean terminal = i == segments.size() - 1;
            if (terminal) {
                Schema.SObjectField field = fieldsOf(current).get(segment.toLowerCase());
                if (field == null) {
                    throw RelatedListException.config('Field "' + rawPath + '" was not found on ' + root.getName() + '.');
                }
                fp.field = field.getDescribe();
                fp.ownerObject = current.getName();
                fp.accessible = fp.accessible && fp.field.isAccessible();
                canonical.add(fp.field.getName());
            } else {
                Schema.DescribeFieldResult rel = relationshipField(current, segment);
                if (rel == null) {
                    throw RelatedListException.config('"' + segment + '" in "' + rawPath + '" is not a relationship on ' + current.getName() + '.');
                }
                List<Schema.SObjectType> targets = rel.getReferenceTo();
                if (targets.size() != 1) {
                    throw RelatedListException.config('"' + segment + '" in "' + rawPath + '" is a polymorphic relationship, which is not supported.');
                }
                fp.accessible = fp.accessible && rel.isAccessible();
                current = targets[0].getDescribe(SObjectDescribeOptions.DEFERRED);
                fp.accessible = fp.accessible && current.isAccessible();
                canonical.add(rel.getRelationshipName());
            }
        }
        fp.path = String.join(canonical, '.');
        fp.prefix = canonical.size() > 1 ? String.join(sliceList(canonical, canonical.size() - 1), '.') + '.' : '';
        return fp;
    }

    private static Schema.DescribeFieldResult relationshipField(Schema.DescribeSObjectResult owner, String relationshipName) {
        Map<String, Schema.SObjectField> fields = fieldsOf(owner);
        String lower = relationshipName.toLowerCase();
        List<String> candidates = new List<String>();
        if (lower.endsWith('__r')) {
            candidates.add(lower.removeEnd('__r') + '__c');
        } else {
            candidates.add(lower + 'id');
        }
        for (String candidate : candidates) {
            Schema.SObjectField f = fields.get(candidate);
            if (f != null) {
                Schema.DescribeFieldResult dfr = f.getDescribe();
                if (dfr.getRelationshipName() != null && dfr.getRelationshipName().equalsIgnoreCase(relationshipName)) {
                    return dfr;
                }
            }
        }
        // Fallback for irregular standard relationship names: full scan (cached describe).
        for (Schema.SObjectField f : fields.values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.getRelationshipName() != null && dfr.getRelationshipName().equalsIgnoreCase(relationshipName)) {
                return dfr;
            }
        }
        return null;
    }

    private static String referenceLabelPath(FieldPath fp) {
        Schema.DescribeFieldResult dfr = fp.field;
        List<Schema.SObjectType> targets = dfr.getReferenceTo();
        if (dfr.getRelationshipName() == null || targets.size() != 1 || fp.depth >= MAX_HOPS) {
            return null;
        }
        Schema.DescribeSObjectResult target = targets[0].getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!target.isAccessible()) {
            return null;
        }
        String nameField = nameFieldOf(target);
        return nameField == null ? null : fp.prefix + dfr.getRelationshipName() + '.' + nameField;
    }

    private static String nameFieldOf(Schema.DescribeSObjectResult objectDescribe) {
        String objectName = objectDescribe.getName();
        if (!nameFieldCache.containsKey(objectName)) {
            String found = null;
            Schema.SObjectField candidate = fieldsOf(objectDescribe).get('name');
            if (candidate != null && candidate.getDescribe().isNameField()) {
                found = candidate.getDescribe().getName();
            } else {
                for (Schema.SObjectField f : fieldsOf(objectDescribe).values()) {
                    Schema.DescribeFieldResult dfr = f.getDescribe();
                    if (dfr.isNameField()) {
                        found = dfr.isAccessible() ? dfr.getName() : null;
                        break;
                    }
                }
            }
            if (found != null && !fieldsOf(objectDescribe).get(found.toLowerCase()).getDescribe().isAccessible()) {
                found = null;
            }
            nameFieldCache.put(objectName, found);
        }
        return nameFieldCache.get(objectName);
    }

    // ===== TYPE MAPPING =====

    private static final Map<Schema.DisplayType, String> UI_TYPES = new Map<Schema.DisplayType, String>{
        Schema.DisplayType.EMAIL => 'email',
        Schema.DisplayType.PHONE => 'phone',
        Schema.DisplayType.URL => 'url',
        Schema.DisplayType.CURRENCY => 'currency',
        Schema.DisplayType.PERCENT => 'percent',
        Schema.DisplayType.DOUBLE => 'number',
        Schema.DisplayType.INTEGER => 'number',
        Schema.DisplayType.LONG => 'number',
        Schema.DisplayType.DATE => 'date',
        Schema.DisplayType.DATETIME => 'datetime',
        Schema.DisplayType.BOOLEAN => 'boolean',
        Schema.DisplayType.PICKLIST => 'picklist',
        Schema.DisplayType.MULTIPICKLIST => 'picklist',
        Schema.DisplayType.ADDRESS => 'address',
        Schema.DisplayType.TEXTAREA => 'textarea'
    };

    private static final Map<Schema.DisplayType, String> FILTER_TYPES = new Map<Schema.DisplayType, String>{
        Schema.DisplayType.STRING => 'text',
        Schema.DisplayType.EMAIL => 'text',
        Schema.DisplayType.PHONE => 'text',
        Schema.DisplayType.URL => 'text',
        Schema.DisplayType.TEXTAREA => 'text',
        Schema.DisplayType.COMBOBOX => 'text',
        Schema.DisplayType.PICKLIST => 'picklist',
        Schema.DisplayType.DOUBLE => 'number',
        Schema.DisplayType.INTEGER => 'number',
        Schema.DisplayType.LONG => 'number',
        Schema.DisplayType.CURRENCY => 'number',
        Schema.DisplayType.PERCENT => 'number',
        Schema.DisplayType.DATE => 'date',
        Schema.DisplayType.DATETIME => 'date',
        Schema.DisplayType.BOOLEAN => 'boolean'
    };

    private static String uiTypeFor(Schema.DisplayType t) {
        return UI_TYPES.containsKey(t) ? UI_TYPES.get(t) : 'text';
    }

    /**
     * @description Filter control type for a field type, or null when filtering is unsupported.
     * @param t field type
     * @return text | picklist | number | date | boolean | null
     */
    public static String filterTypeFor(Schema.DisplayType t) {
        return FILTER_TYPES.get(t);
    }

    private static String labelFor(FieldPath fp) {
        String label = fp.field.getLabel();
        if (fp.depth > 0) {
            return describeObjectSafe(fp.ownerObject) + ': ' + label;
        }
        return label;
    }

    private static String describeObjectSafe(String objectName) {
        Schema.DescribeSObjectResult d = objectCache.get(objectName.toLowerCase());
        return d == null ? objectName : d.getLabel();
    }

    // ===== DESCRIBE CACHE =====

    /**
     * @description Describes an object by API name with a configuration error on unknown names.
     * @param objectName API name
     * @param role human-readable role for the error message
     * @return describe
     */
    public static Schema.DescribeSObjectResult describeObject(String objectName, String role) {
        if (String.isBlank(objectName) || !IDENTIFIER.matcher(objectName.trim()).matches()) {
            throw RelatedListException.config(role + ' is missing or not a valid API name.');
        }
        String lower = objectName.trim().toLowerCase();
        if (!objectCache.containsKey(lower)) {
            List<Schema.DescribeSObjectResult> results;
            try {
                results = Schema.describeSObjects(new List<String>{ objectName.trim() }, SObjectDescribeOptions.DEFERRED);
            } catch (Exception e) {
                results = new List<Schema.DescribeSObjectResult>();
            }
            if (results.isEmpty()) {
                throw RelatedListException.config(role + ' "' + objectName.trim() + '" was not found.');
            }
            objectCache.put(lower, results[0]);
        }
        return objectCache.get(lower);
    }

    private static Map<String, Schema.SObjectField> fieldsOf(Schema.DescribeSObjectResult objectDescribe) {
        String key = objectDescribe.getName().toLowerCase();
        if (!objectCache.containsKey(key)) {
            objectCache.put(key, objectDescribe);
        }
        if (!fieldCache.containsKey(key)) {
            Map<String, Schema.SObjectField> lowered = new Map<String, Schema.SObjectField>();
            Map<String, Schema.SObjectField> raw = objectDescribe.fields.getMap();
            for (String name : raw.keySet()) {
                lowered.put(name.toLowerCase(), raw.get(name));
            }
            fieldCache.put(key, lowered);
        }
        return fieldCache.get(key);
    }

    private static Integer visibleCount(ResolvedList rl) {
        Integer count = 0;
        for (ResolvedColumn col : rl.columns) {
            if (col.visible) {
                count++;
            }
        }
        return count;
    }

    private static List<String> sliceList(List<String> values, Integer endExclusive) {
        List<String> result = new List<String>();
        for (Integer i = 0; i < endExclusive; i++) {
            result.add(values[i]);
        }
        return result;
    }
}
