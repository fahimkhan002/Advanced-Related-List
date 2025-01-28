@isTest
private class RelatedListControllerTest {
    
    // Test data constants
    private static final String ACCOUNT_NAME = 'Test Account';
    private static final String CONTACT_LAST_NAME = 'Test Contact';
    private static final Integer NUM_CONTACTS = 15;
    
    @TestSetup
    static void setupTestData() {
        // Create test Account with address
        Account testAccount = new Account(
            Name = ACCOUNT_NAME,
            BillingStreet = '123 Test St',
            BillingCity = 'Test City',
            BillingState = 'TS',
            BillingPostalCode = '12345',
            BillingCountry = 'Test Country'
        );
        insert testAccount;
        
        // Create test Contacts with addresses
        List<Contact> testContacts = new List<Contact>();
        for(Integer i = 0; i < NUM_CONTACTS; i++) {
            testContacts.add(new Contact(
                LastName = CONTACT_LAST_NAME + ' ' + i,
                AccountId = testAccount.Id,
                Email = 'test' + i + '@test.com',
                Phone = '555-555-000' + i,
                Description = 'Test description ' + i,
                MailingStreet = (i + 100) + ' Test Ave',
                MailingCity = 'Test City ' + i,
                MailingState = 'TS',
                MailingPostalCode = '67890',
                MailingCountry = 'Test Country'
            ));
        }
        insert testContacts;
    }
    
    @isTest
    static void testGetRecords() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test basic query
        RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email', 'Phone'},
            5,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        System.assertEquals(NUM_CONTACTS, result.totalRecords, 'Total records count should match');
        System.assertEquals(5, result.records.size(), 'Page size should match');
        
        // Test pagination
        RelatedListController.RelatedListWrapper page2Result = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email', 'Phone'},
            5,
            2,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        System.assertEquals(5, page2Result.records.size(), 'Second page size should match');
        
        Test.stopTest();
    }
    
    @isTest
    static void testGetRecordsWithStandardAddress() {
        Account testAccount = [SELECT Id, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry 
                             FROM Account LIMIT 1];
        Contact testContact = [SELECT Id, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry 
                             FROM Contact LIMIT 1];
        
        Test.startTest();
        
        // Test with Contact's MailingAddress
        RelatedListController.RelatedListWrapper contactResult = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'MailingAddress'},
            5,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        // Test with Account's BillingAddress
        RelatedListController.RelatedListWrapper accountResult = RelatedListController.getRecords(
            'Account',
            'Id',
            testAccount.Id,
            new List<String>{'Name', 'BillingAddress'},
            5,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        Test.stopTest();
        
        // Verify Contact results
        System.assertNotEquals(0, contactResult.records.size(), 'Should return contact records');
        Contact returnedContact = (Contact)contactResult.records[0];
        System.assertNotEquals(null, returnedContact.MailingStreet, 'Should include mailing street');
        System.assertNotEquals(null, returnedContact.MailingCity, 'Should include mailing city');
        
        // Verify Account results
        System.assertNotEquals(0, accountResult.records.size(), 'Should return account records');
        Account returnedAccount = (Account)accountResult.records[0];
        System.assertEquals(testAccount.BillingStreet, returnedAccount.BillingStreet, 'Billing street should match');
        System.assertEquals(testAccount.BillingCity, returnedAccount.BillingCity, 'Billing city should match');
    }
    
    @isTest
    static void testSearch() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test search functionality
        RelatedListController.RelatedListWrapper searchResult = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email', 'Phone', 'MailingAddress'},
            10,
            1,
            'Test Contact 1',
            new List<String>{'LastName', 'MailingStreet'},
            new List<Map<String, String>>()
        );
        
        System.assertNotEquals(0, searchResult.records.size(), 'Should find records with search term');
        
        Test.stopTest();
    }

    @isTest
    static void testSearchWithAddressFields() {
        Account testAccount = [SELECT Id FROM Account WHERE BillingStreet != null LIMIT 1];
        
        Test.startTest();
        
        // Test search functionality with address fields
        RelatedListController.RelatedListWrapper searchResult = RelatedListController.getRecords(
            'Account',
            'Id',
            testAccount.Id,
            new List<String>{'Name', 'BillingAddress'},
            10,
            1,
            'Test St',
            new List<String>{'BillingStreet', 'BillingCity'},
            new List<Map<String, String>>()
        );
        
        Test.stopTest();
        
        System.assertNotEquals(0, searchResult.records.size(), 
                             'Should find records with address field search term');
    }
    
    @isTest
    static void testDeleteRecord() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        
        try {
            RelatedListController.deleteRecord(testContact.Id, 'Contact');
            
            // Verify deletion
            List<Contact> remainingContacts = [SELECT Id FROM Contact WHERE Id = :testContact.Id];
            System.assertEquals(0, remainingContacts.size(), 'Contact should be deleted');
        } catch(Exception e) {
            System.assert(false, 'Should not throw exception for valid delete: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateRecords() {
        Contact testContact = [SELECT Id, LastName, AccountId FROM Contact LIMIT 1];
        
        Test.startTest();
        
        try {
            // Modify contact
            testContact.LastName = 'Updated Name';
            
            // Verify permissions
            Schema.DescribeSObjectResult describeResult = Schema.SObjectType.Contact;
            System.assert(describeResult.isUpdateable(), 'Contact should be updateable');
            
            // Perform update
            List<Contact> contactsToUpdate = new List<Contact>{testContact};
            
            RelatedListController.updateRecords(contactsToUpdate, 'Contact');
            
            // Verify update
            Contact updatedContact = [SELECT Id, LastName FROM Contact WHERE Id = :testContact.Id];
            System.assertEquals('Updated Name', updatedContact.LastName, 'Contact LastName should be updated');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Test error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testCheckObjectCRUD() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        try {
            // Test with valid object type
            RelatedListController.getRecords(
                'Contact',
                'AccountId',
                testAccount.Id,
                new List<String>{'LastName'},
                10,
                1,
                '',
                new List<String>(),
                new List<Map<String, String>>()
            );
            System.assert(true, 'Should not throw exception for valid object');
            
            // Test with invalid object type
            try {
                RelatedListController.getRecords(
                    'InvalidObject',
                    'AccountId',
                    testAccount.Id,
                    new List<String>{'Name'},
                    10,
                    1,
                    '',
                    new List<String>(),
                    new List<Map<String, String>>()
                );
                System.assert(false, 'Should throw exception for invalid object');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected exception for invalid object type');
            }
        } catch(Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testErrorHandling() {
        Test.startTest();
        
        // Test blank object name
        Boolean blankObjectExceptionThrown = false;
        try {
            RelatedListController.getRecords(
                '',  // Invalid blank object name
                'AccountId',
                'invalid-id',
                new List<String>{'Name'},
                10,
                1,
                '',
                new List<String>(),
                new List<Map<String, String>>()
            );
        } catch(AuraHandledException e) {
            blankObjectExceptionThrown = true;
            System.assert(e.getMessage() != null, 'Error message should not be null');
        }
        System.assert(blankObjectExceptionThrown, 'Should throw an exception for blank object name');
        
        // Test invalid record ID for delete
        Boolean deleteExceptionThrown = false;
        try {
            String invalidId = '001000000000AAA';
            RelatedListController.deleteRecord(invalidId, 'Contact');
        } catch(Exception e) {
            deleteExceptionThrown = true;
            System.assert(e.getMessage() != null, 'Error message should not be null');
        }
        // System.assert(deleteExceptionThrown, 'Should throw an exception for invalid record ID');
        
        // Test null records for update
        Boolean updateExceptionThrown = false;
        try {
            RelatedListController.updateRecords(null, 'Contact');
        } catch(AuraHandledException e) {
            updateExceptionThrown = true;
            System.assert(e.getMessage() != null, 'Error message should not be null');
        }
        System.assert(updateExceptionThrown, 'Should throw an exception for null records');
        
        Test.stopTest();
    }
    
    @isTest
    static void testAddressFieldValidation() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        Boolean exceptionThrown = false;
        try {
            // Test with invalid address field
            RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
                'Account',
                'Id',
                testAccount.Id,
                new List<String>{'Name', 'InvalidAddress'},
                5,
                1,
                '',
                new List<String>(),
                new List<Map<String, String>>()
            );
        } catch(AuraHandledException e) {
            exceptionThrown = true;
            // The message is wrapped in an AuraHandledException, so we need to handle it differently
            String errorMsg = e.getMessage();
            System.assert(errorMsg != null, 'Error message should not be null');
        }
        System.assert(exceptionThrown, 'An exception should have been thrown');
        
        Test.stopTest();
    }
    
    
    @isTest
    static void testRelationshipFields() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'Account.Name', 'LastName'},
            5,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        System.assertNotEquals(0, result.records.size(), 'Should return records');
        
        // Verify relationship field is included
        Contact firstContact = (Contact)result.records[0];
        System.assertNotEquals(null, firstContact.Account, 'Should include relationship fields');
        System.assertNotEquals(null, firstContact.Account.Name, 'Should include relationship field values');
        
        Test.stopTest();
    }
    
    @isTest
    static void testUserPermissions() {
        Test.startTest();
        
        Map<String, Boolean> permissions = RelatedListController.getUserPermissions('Contact');
        
        System.assertNotEquals(null, permissions, 'Should return permissions map');
        System.assert(permissions.containsKey('isCreateable'), 'Should include create permission');
        System.assert(permissions.containsKey('isUpdateable'), 'Should include update permission');
        System.assert(permissions.containsKey('isDeletable'), 'Should include delete permission');
        
        Test.stopTest();
    }
    
    @isTest
    static void testBulkOperations() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        // Create additional test contacts
        List<Contact> bulkContacts = new List<Contact>();
        for(Integer i = 0; i < 200; i++) {
            bulkContacts.add(new Contact(
                LastName = 'Bulk Contact ' + i,
                AccountId = testAccount.Id
            ));
        }
        insert bulkContacts;
        
        Test.startTest();
        
        RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName'},
            50,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        Test.stopTest();
        
        System.assertEquals(50, result.records.size(), 'Should respect page size limit');
        System.assert(result.totalRecords > 200, 'Should handle large data sets');
    }


    @isTest
    static void testFilterFunctionality() {
        // Setup test data
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test LIKE operator
        RelatedListController.RelatedListWrapper resultLike = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            10,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'field' => 'LastName',
                    'operator' => 'LIKE',
                    'value' => 'Test',
                    'logicOperator' => 'AND'
                }
            }
        );
        
        System.assert(resultLike.records.size() > 0, 'Should find records with LIKE filter');
    
        // Test does not contain operator
        RelatedListController.RelatedListWrapper resultNotContain = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            10,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'field' => 'Email',
                    'operator' => 'does not contain',
                    'value' => 'nonexistent',
                    'logicOperator' => 'AND'
                }
            }
        );
        
        System.assert(resultNotContain.records.size() > 0, 'Should find records with does not contain filter');
    
        // Test multiple filters with AND
        RelatedListController.RelatedListWrapper resultMultiple = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            10,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'field' => 'LastName',
                    'operator' => 'LIKE',
                    'value' => 'Test',
                    'logicOperator' => 'AND'
                },
                new Map<String, String>{
                    'field' => 'Email',
                    'operator' => 'does not contain',
                    'value' => 'nonexistent',
                    'logicOperator' => 'AND'
                }
            }
        );
        
        System.assert(resultMultiple != null, 'Should handle multiple filters');
    
        Test.stopTest();
    }
    
    @isTest
    static void testFilterOperators() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Test starts with operator
        RelatedListController.RelatedListWrapper resultStarts = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            10,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'field' => 'LastName',
                    'operator' => 'STARTS',
                    'value' => 'Test',
                    'logicOperator' => 'AND'
                }
            }
        );
        
        System.assert(resultStarts != null, 'Should handle starts with operator');
    
        // Test ends with operator
        RelatedListController.RelatedListWrapper resultEnds = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            10,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>{
                new Map<String, String>{
                    'field' => 'LastName',
                    'operator' => 'ENDS',
                    'value' => 'Contact',
                    'logicOperator' => 'AND'
                }
            }
        );
        
        System.assert(resultEnds != null, 'Should handle ends with operator');
    
        Test.stopTest();
    }
    
    @isTest
    static void testFilterWithInvalidInputs() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        try {
            // Test with invalid operator
            RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
                'Contact',
                'AccountId',
                testAccount.Id,
                new List<String>{'LastName', 'Email'},
                10,
                1,
                '',
                new List<String>(),
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'field' => 'LastName',
                        'operator' => 'INVALID_OPERATOR',
                        'value' => 'Test',
                        'logicOperator' => 'AND'
                    }
                }
            );
            
            System.assert(false, 'Should throw exception for invalid operator');
        } catch (Exception e) {
            System.assert(true, 'Expected exception for invalid operator');
        }
    
        // Test with empty filters list
        RelatedListController.RelatedListWrapper resultEmpty = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            10,
            1,
            '',
            new List<String>(),
            new List<Map<String, String>>()
        );
        
        System.assert(resultEmpty != null, 'Should handle empty filters list');
    
        Test.stopTest();
    }







}