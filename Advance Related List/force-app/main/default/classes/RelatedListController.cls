/**
 * @description Controller class for the Advanced Related List LWC component with security checks
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
        
        public RelatedListWrapper(List<SObject> records, Integer totalRecords) {
            this.records = records;
            this.totalRecords = totalRecords;
        }
    }

    /**
     * @description Custom exception for security violations
     */
    public class SecurityException extends Exception {}
    
    // ===== SECURITY UTILITY METHODS =====
    
    /**
     * @description Checks object-level CRUD permissions
     * @param objectType The SObject type to check
     * @param operation The CRUD operation to check (CREATE, READ, UPDATE, DELETE)
     * @throws SecurityException if the user lacks required permissions
     */
    private static void checkObjectCRUD(String objectType, String operation) {
        try {
            // First verify the object type exists
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectType);
            if (sObjectType == null) {
                throw new SecurityException('Invalid object type: ' + objectType);
            }
            
            Schema.DescribeSObjectResult describe = sObjectType.getDescribe();
            Boolean hasPermission = false;
            String errorMsg = '';
            
            switch on operation.toUpperCase() {
                when 'CREATE' {
                    hasPermission = describe.isCreateable();
                    errorMsg = 'create';
                }
                when 'READ' {
                    hasPermission = describe.isAccessible();
                    errorMsg = 'read';
                }
                when 'UPDATE' {
                    hasPermission = describe.isUpdateable();
                    errorMsg = 'update';
                }
                when 'DELETE' {
                    hasPermission = describe.isDeletable();
                    errorMsg = 'delete';
                }
            }
            
            if (!hasPermission) {
                throw new SecurityException('Insufficient permissions to ' + errorMsg + ' ' + objectType + ' records');
            }
        } catch (Exception e) {
            throw new SecurityException('Error checking permissions: ' + e.getMessage());
        }
    }
    
    /**
     * @description Checks field-level security for a list of fields
     * @param objectType The API name of the object
     * @param fields List of field API names
     * @param operation The operation to check (READ or EDIT)
     * @throws SecurityException if the user lacks required permissions
     */
    private static void checkFieldSecurity(String objectType, List<String> fields, String operation) {
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectType).getDescribe().fields.getMap();
        Set<String> processedFields = new Set<String>();
        
        for (String field : fields) {
            // Handle relationship fields
            if (field.contains('.')) {
                String baseField = field.split('\\.')[0];
                if (!processedFields.contains(baseField)) {
                    processedFields.add(baseField);
                    checkFieldAccess(fieldMap, baseField, operation);
                }
                continue;
            }
            
            if (!processedFields.contains(field)) {
                processedFields.add(field);
                checkFieldAccess(fieldMap, field, operation);
            }
        }
    }
    
    /**
     * @description Checks access for a single field
     * @param fieldMap Map of field descriptors
     * @param fieldName Field API name
     * @param operation Operation to check
     * @throws SecurityException if the user lacks required permissions
     */
    private static void checkFieldAccess(Map<String, Schema.SObjectField> fieldMap, String fieldName, String operation) {
        Schema.SObjectField field = fieldMap.get(fieldName);
        if (field == null) return; // Skip non-existent fields
        
        Schema.DescribeFieldResult describe = field.getDescribe();
        Boolean hasPermission = operation.toUpperCase() == 'READ' ? 
            describe.isAccessible() : describe.isUpdateable();
            
        if (!hasPermission) {
            throw new SecurityException('Insufficient permissions to ' + operation.toLowerCase() + 
                                     ' field: ' + fieldName);
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
            // Security checks
            checkObjectCRUD(childObject, 'READ');
            checkFieldSecurity(childObject, fields, 'READ');
            
            // Additional security check for searchable fields
            if (!searchableFields.isEmpty()) {
                checkFieldSecurity(childObject, searchableFields, 'READ');
            }

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

        } catch (SecurityException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            handleException(e);
            return null;
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
            // Security check
            checkObjectCRUD(objectName, 'DELETE');
            
            // Validate inputs
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID cannot be blank.');
            }

            // Query the record first to ensure it exists and user has access
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectName) +
                         ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\' LIMIT 1';
            
            List<SObject> records = Database.query(query);
            if (!records.isEmpty()) {
                delete records[0];
            }
        } catch (SecurityException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            handleException(e);
        }
    }

    /**
     * @description Updates a list of records
     * @param records List of records to update
     * @param objectName API name of the object
     */
    @AuraEnabled
    public static void updateRecords(List<SObject> records, String objectName) {
        try {
            System.debug('Starting updateRecords method');
            System.debug('Records to update: ' + records);
            System.debug('Object name: ' + objectName);
            
            // Input validation
            if (records == null || records.isEmpty()) {
                throw new AuraHandledException('No records provided for update.');
            }
    
            // Basic security check
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectName);
            if (sObjectType == null) {
                throw new AuraHandledException('Invalid object type: ' + objectName);
            }
    
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            if (!describeResult.isUpdateable()) {
                throw new AuraHandledException('Insufficient permissions to update ' + objectName);
            }
    
            // Update records
            Database.SaveResult[] results = Database.update(records, false);
            
            // Check results
            List<String> errors = new List<String>();
            for (Database.SaveResult result : results) {
                if (!result.isSuccess()) {
                    for (Database.Error err : result.getErrors()) {
                        errors.add(err.getMessage());
                    }
                }
            }
            
            if (!errors.isEmpty()) {
                throw new AuraHandledException(String.join(errors, '. '));
            }
    
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in updateRecords: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

            @AuraEnabled(cacheable=true)
        public static Map<String, Boolean> getUserPermissions(String objectName) {
            try {
                Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(objectName).getDescribe();
                return new Map<String, Boolean>{
                    'isCreateable' => describe.isCreateable(),
                    'isUpdateable' => describe.isUpdateable(),
                    'isDeletable' => describe.isDeletable()
                };
            } catch (Exception e) {
                throw new AuraHandledException(e.getMessage());
            }
        }

    // ===== PRIVATE HELPER METHODS =====

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

    private static Set<String> buildQueryFields(List<String> fields) {
        Set<String> queryFields = new Set<String>{'Id'};
        queryFields.addAll(fields);
        return queryFields;
    }

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
            String searchValue = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            
            for (String field : searchableFields) {
                searchConditions.add(String.escapeSingleQuotes(field) + ' LIKE \'' + searchValue + '\'');
            }
            
            if (!searchConditions.isEmpty()) {
                whereClause += ' AND (' + String.join(searchConditions, ' OR ') + ')';
            }
        }

        return whereClause;
    }

    private static Integer getTotalRecords(String childObject, String whereClause) {
        return Database.countQuery(
            'SELECT COUNT() FROM ' + String.escapeSingleQuotes(childObject) + 
            ' WHERE ' + whereClause
        );
    }

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
                      ' ORDER BY CreatedDate DESC' +
                      ' LIMIT :pageSize OFFSET :offset';

        return Database.query(query);
    }

    private static void handleException(Exception e) {
        String errorMessage = 'Error: ' + e.getMessage();
        System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        throw new AuraHandledException(errorMessage);
    }
}