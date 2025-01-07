public with sharing class RelatedListController {
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
            // Build the base query fields
            Set<String> queryFields = new Set<String>{'Id', 'Name'};
            
            // Add all fields including relationship fields
            for(String field : fields) {
                if(field.contains('__r.')) {
                    // For relationship fields, we need to add the whole path
                    queryFields.add(field);
                } else {
                    queryFields.add(field);
                }
            }

            // Build the WHERE clause
            String whereClause = String.escapeSingleQuotes(parentLookupField) + 
                               ' = \'' + String.escapeSingleQuotes(parentId) + '\'';

            // Add search conditions if searchTerm is provided
            if (String.isNotBlank(searchTerm)) {
                List<String> searchConditions = new List<String>();
                String searchValue = '%' + String.escapeSingleQuotes(searchTerm) + '%';
                
                for (String field : searchableFields) {
                    if (field.contains('__r.')) {
                        searchConditions.add(field + ' LIKE :searchValue');
                    } else {
                        searchConditions.add(field + ' LIKE :searchValue');
                    }
                }
                
                if (!searchConditions.isEmpty()) {
                    whereClause += ' AND (' + String.join(searchConditions, ' OR ') + ')';
                }
            }

            // Debug the query fields
            System.debug('Query Fields: ' + queryFields);
            
            // Build final queries
            String baseQuery = 'FROM ' + String.escapeSingleQuotes(childObject) + 
                             ' WHERE ' + whereClause;
            
            // Get total filtered count
            Integer totalRecords = Database.countQuery('SELECT COUNT() ' + baseQuery);

            // Get paginated records
            String queryStr = 'SELECT ' + String.join(new List<String>(queryFields), ',') + 
                            ' ' + baseQuery + 
                            ' ORDER BY CreatedDate DESC' +
                            ' LIMIT :pageSize OFFSET :offset';

            // Debug the final query
            System.debug('Final Query: ' + queryStr);

            Integer offset = (pageNumber - 1) * pageSize;
            List<SObject> records = Database.query(queryStr);

            return new RelatedListWrapper(records, totalRecords);
            
        } catch (Exception e) {
            System.debug('Error in getRecords: ' + e.getMessage());
            System.debug('Error stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteRecord(String recordId, String objectName) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID cannot be blank.');
            }
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(objectName) +
                         ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\' LIMIT 1';
            SObject record = Database.query(query);

            if (record != null) {
                delete record;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting record: ' + e.getMessage());
        }
    }

    public class RelatedListWrapper {
        @AuraEnabled public List<SObject> records;
        @AuraEnabled public Integer totalRecords;

        public RelatedListWrapper(List<SObject> records, Integer totalRecords) {
            this.records = records;
            this.totalRecords = totalRecords;
        }
    }
}