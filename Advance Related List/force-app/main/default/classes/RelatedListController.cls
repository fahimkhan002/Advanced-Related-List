public with sharing class RelatedListController {
    @AuraEnabled(cacheable=true)
    public static RelatedListWrapper getRecords(
        String childObject,
        String parentLookupField,
        String parentId,
        List<String> fields,
        Integer pageSize,
        Integer pageNumber
    ) {
        try {
            // Debug input parameters            System.debug('getRecords Input Parameters:');
            System.debug('Child Object: ' + childObject);
            System.debug('Parent Lookup Field: ' + parentLookupField);
            System.debug('Parent ID: ' + parentId);
            System.debug('Fields: ' + fields);
            System.debug('Page Size: ' + pageSize);
            System.debug('Page Number: ' + pageNumber);

            
            Integer offset = (pageNumber - 1) * pageSize;
            
            // Build the dynamic query
            Set<String> queryFields = new Set<String>{'Id', 'Name'};
            queryFields.addAll(fields);
            
            // Build the query string
            String queryStr = 'SELECT ' + String.join(new List<String>(queryFields), ',') +
                           ' FROM ' + String.escapeSingleQuotes(childObject) +
                           ' WHERE ' + String.escapeSingleQuotes(parentLookupField) + ' = \'' + String.escapeSingleQuotes(parentId) + '\'' +
                           ' ORDER BY CreatedDate DESC' +
                           ' LIMIT ' + pageSize + ' OFFSET ' + offset;
            

            List<SObject> records = Database.query(queryStr);
            System.debug('Executing Query: ' + queryStr);
            
            List<SObject> records = Database.query(queryStr);
            System.debug('Query Results: ' + records);

    
            // Get total count
            String countQuery = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(childObject) +
                              ' WHERE ' + String.escapeSingleQuotes(parentLookupField) + ' = \'' + String.escapeSingleQuotes(parentId) + '\'';
            
            Integer totalRecords = Database.countQuery(countQuery);
            System.debug('Total Records: ' + totalRecords);

            
            return new RelatedListWrapper(records, totalRecords);
            
        } catch (Exception e) {

            System.debug('Error in getRecords: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
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