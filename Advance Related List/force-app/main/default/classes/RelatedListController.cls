/**
 * @description Controller class for the Advanced Related List LWC component
 * @author Your Name
 * @date 2025-01-15
 */
public with sharing class RelatedListController {
    
    // ===== INNER CLASSES =====
    
    /**
     * @description Wrapper class to hold the response data for the related list
     */
    public class RelatedListWrapper {
        @AuraEnabled public List<SObject> records;
        @AuraEnabled public Integer totalRecords;

        /**
         * @description Constructor to initialize the wrapper
         * @param records List of records to display
         * @param totalRecords Total count of records
         */
        public RelatedListWrapper(List<SObject> records, Integer totalRecords) {
            this.records = records;
            this.totalRecords = totalRecords;
        }
    }

    // ===== PUBLIC METHODS =====

    /**
     * @description Gets paginated records for the related list with search functionality
     * @param childObject API name of the child object
     * @param parentLookupField API name of the lookup field on child object
     * @param parentId Id of the parent record
     * @param fields List of fields to query
     * @param pageSize Number of records per page
     * @param pageNumber Current page number
     * @param searchTerm Search string to filter records
     * @param searchableFields List of fields to search in
     * @return RelatedListWrapper Instance containing records and total count
     */
    @AuraEnabled(cacheable=true)
    public static RelatedListWrapper getRecords(
        String childObject,
        String parentLookupField,
        String parentId,
        List<String> fields,
        Integer pageSize,
        Integer pageNumber,
        String searchTerm,
        List<String> searchableFields
    ) {
        try {
            // Validate inputs
            validateInputs(childObject, parentLookupField, parentId, fields);

            // Build query fields
            Set<String> queryFields = buildQueryFields(fields);

            // Build WHERE clause
            String whereClause = buildWhereClause(
                parentLookupField, 
                parentId, 
                searchTerm, 
                searchableFields
            );

            // Get total record count
            Integer totalRecords = getTotalRecords(childObject, whereClause);

            // Build and execute main query
            List<SObject> records = executeMainQuery(
                childObject,
                queryFields,
                whereClause,
                pageSize,
                pageNumber
            );

            return new RelatedListWrapper(records, totalRecords);

        } catch (Exception e) {
            handleException(e);
            return null; // This line will never execute due to exception handling
        }
    }

    /**
     * @description Deletes a specific record
     * @param recordId Id of the record to delete
     * @param objectName API name of the object
     */
    @AuraEnabled
    public static void deleteRecord(String recordId, String objectName) {
        try {
            // Validate inputs
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID cannot be blank.');
            }

            // Build and execute query
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectName) +
                         ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\' LIMIT 1';
            
            SObject record = Database.query(query);

            if (record != null) {
                delete record;
            }
        } catch (Exception e) {
            handleException(e);
        }
    }

    /**
     * @description Updates a list of records
     * @param records List of records to update
     */
    @AuraEnabled
    public static void updateRecords(List<SObject> records) {
        try {
            update records;
        } catch (Exception e) {
            handleException(e);
        }
    }

    // ===== PRIVATE HELPER METHODS =====

    /**
     * @description Validates input parameters
     * @param childObject Child object API name
     * @param parentLookupField Parent lookup field name
     * @param parentId Parent record Id
     * @param fields List of fields to query
     */
    private static void validateInputs(
        String childObject,
        String parentLookupField,
        String parentId,
        List<String> fields
    ) {
        if (String.isBlank(childObject)) {
            throw new AuraHandledException('Child object name cannot be blank.');
        }
        if (String.isBlank(parentLookupField)) {
            throw new AuraHandledException('Parent lookup field cannot be blank.');
        }
        if (String.isBlank(parentId)) {
            throw new AuraHandledException('Parent ID cannot be blank.');
        }
        if (fields == null || fields.isEmpty()) {
            throw new AuraHandledException('Fields list cannot be empty.');
        }
    }

    /**
     * @description Builds the set of fields to query
     * @param fields List of fields from the component
     * @return Set<String> Set of fields to query
     */
    private static Set<String> buildQueryFields(List<String> fields) {
        Set<String> queryFields = new Set<String>{'Id', 'Name'};
        
        for(String field : fields) {
            queryFields.add(field);
        }
        
        return queryFields;
    }

    /**
     * @description Builds the WHERE clause for the query
     * @param parentLookupField Parent lookup field name
     * @param parentId Parent record Id
     * @param searchTerm Search string
     * @param searchableFields List of searchable fields
     * @return String WHERE clause
     */
    private static String buildWhereClause(
        String parentLookupField,
        String parentId,
        String searchTerm,
        List<String> searchableFields
    ) {
        String whereClause = String.escapeSingleQuotes(parentLookupField) + 
                        ' = \'' + String.escapeSingleQuotes(parentId) + '\'';

        if (String.isNotBlank(searchTerm) && searchableFields != null && !searchableFields.isEmpty()) {
            List<String> searchConditions = new List<String>();
            // Create the search value with escaped special characters
            String searchValue = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            
            for (String field : searchableFields) {
                // Instead of using bind variable, directly include the search value
                searchConditions.add(field + ' LIKE \'' + searchValue + '\'');
            }
            
            if (!searchConditions.isEmpty()) {
                whereClause += ' AND (' + String.join(searchConditions, ' OR ') + ')';
            }
        }

        return whereClause;
    }

    /**
     * @description Gets the total count of records matching the criteria
     * @param childObject Child object API name
     * @param whereClause WHERE clause for the query
     * @return Integer Total number of records
     */
    private static Integer getTotalRecords(String childObject, String whereClause) {
        return Database.countQuery(
            'SELECT COUNT() FROM ' + String.escapeSingleQuotes(childObject) + 
            ' WHERE ' + whereClause
        );
    }

    /**
     * @description Executes the main query to get records
     * @param childObject Child object API name
     * @param queryFields Set of fields to query
     * @param whereClause WHERE clause
     * @param pageSize Number of records per page
     * @param pageNumber Current page number
     * @return List<SObject> List of records
     */
    private static List<SObject> executeMainQuery(
        String childObject,
        Set<String> queryFields,
        String whereClause,
        Integer pageSize,
        Integer pageNumber
    ) {
        Integer offset = (pageNumber - 1) * pageSize;
        
        String query = 'SELECT ' + String.join(new List<String>(queryFields), ',') + 
                      ' FROM ' + String.escapeSingleQuotes(childObject) + 
                      ' WHERE ' + whereClause + 
                      ' ORDER BY CreatedDate ASC' +
                      ' LIMIT :pageSize OFFSET :offset';

        return Database.query(query);
    }

    /**
     * @description Handles exceptions by wrapping them in AuraHandledException
     * @param e Exception to handle
     */
    private static void handleException(Exception e) {
        String errorMessage = 'Error: ' + e.getMessage();
        System.debug('Error: ' + e.getMessage());
        System.debug('Stack trace: ' + e.getStackTraceString());
        throw new AuraHandledException(errorMessage);
    }
}