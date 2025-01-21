@isTest
private class RelatedListControllerTest {
    
    // Test data constants
    private static final String ACCOUNT_NAME = 'Test Account';
    private static final String CONTACT_LAST_NAME = 'Test Contact';
    private static final Integer NUM_CONTACTS = 15;
    
    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
            Name = ACCOUNT_NAME
        );
        insert testAccount;
        
        // Create test Contacts
        List<Contact> testContacts = new List<Contact>();
        for(Integer i = 0; i < NUM_CONTACTS; i++) {
            testContacts.add(new Contact(
                LastName = CONTACT_LAST_NAME + ' ' + i,
                AccountId = testAccount.Id,
                Email = 'test' + i + '@test.com',
                Phone = '555-555-000' + i,
                Description = 'Test description ' + i
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
            new List<String>()
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
            new List<String>()
        );
        
        System.assertEquals(5, page2Result.records.size(), 'Second page size should match');
        
        Test.stopTest();
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
            new List<String>{'LastName', 'Email', 'Phone'},
            10,
            1,
            'Test Contact 1',
            new List<String>{'LastName'}
        );
        
        System.assertNotEquals(0, searchResult.records.size(), 'Should find records with search term');
        
        Test.stopTest();
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
        // Create test data
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        System.assertNotEquals(null, testAccount.Id, 'Account should be created');
        
        Contact testContact = new Contact(
            LastName = 'Test Contact',
            AccountId = testAccount.Id
        );
        insert testContact;
        System.assertNotEquals(null, testContact.Id, 'Contact should be created');
        
        Test.startTest();
        
        try {
            // Refresh contact data
            Contact contactToUpdate = [SELECT Id, LastName, AccountId 
                                     FROM Contact 
                                     WHERE Id = :testContact.Id];
            
            // Verify data before update
            System.assertNotEquals(null, contactToUpdate, 'Contact should be found');
            System.debug('Contact before update: ' + contactToUpdate);
            
            // Modify contact
            contactToUpdate.LastName = 'Updated Name';
            
            // Verify permissions
            Schema.DescribeSObjectResult describeResult = Schema.SObjectType.Contact;
            System.assert(describeResult.isUpdateable(), 'Contact should be updateable');
            
            
            // Perform update
            List<Contact> contactsToUpdate = new List<Contact>{contactToUpdate};
            System.debug('Contacts to update: ' + contactsToUpdate);
            
            RelatedListController.updateRecords(contactsToUpdate, 'Contact');
            
            // Verify update
            Contact updatedContact = [SELECT Id, LastName 
                                    FROM Contact 
                                    WHERE Id = :testContact.Id];
            
            System.assertEquals('Updated Name', updatedContact.LastName, 
                              'Contact LastName should be updated');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Test error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
        
        Test.stopTest();
    }
    
    // Helper method to create test user
    private static User createTestUser() {
        // Query for System Administrator profile instead as it's always available
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        String uniqueUserName = 'standarduser' + DateTime.now().getTime() + '@testorg.com';
        User u = new User(
            Alias = 'standt',
            Email = uniqueUserName,
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = uniqueUserName
        );
        
        insert u;
        
        // Remove PermissionSet assignment as it might not exist
        /* Commenting out PermissionSet section
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'YourPermissionSet' LIMIT 1];
        if(ps != null) {
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = ps.Id
            );
        }
        */
        
        return u;
    }

    @isTest
static void testCheckObjectCRUD() {
    Test.startTest();
    
    try {
        // Test with valid object type
        RelatedListController.getRecords(
            'Contact',
            'AccountId',
            [SELECT Id FROM Account LIMIT 1].Id,
            new List<String>{'LastName'},
            10,
            1,
            '',
            new List<String>()
        );
        System.assert(true, 'Should not throw exception for valid object');
        
        // Test with invalid object type
        try {
            RelatedListController.getRecords(
                'InvalidObject',
                'AccountId',
                [SELECT Id FROM Account LIMIT 1].Id,
                new List<String>{'Name'},
                10,
                1,
                '',
                new List<String>()
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
        try {
            RelatedListController.getRecords(
                '',  // Invalid blank object name
                'AccountId',
                'invalid-id',
                new List<String>{'Name'},
                10,
                1,
                '',
                new List<String>()
            );
            System.assert(false, 'Should throw an exception for blank object name');
        } catch(AuraHandledException e) {
            // Expected exception
        }
        
        // Test invalid record ID for delete
        String invalidId = '001000000000AAA';
        try {
            RelatedListController.deleteRecord(invalidId, 'Contact');
            List<Contact> contacts = [SELECT Id FROM Contact WHERE Id = :invalidId];
            System.assert(contacts.isEmpty(), 'No records should be found');
        } catch(Exception e) {
            // Expected behavior - no assertion needed
        }
        
        // Test null records for update
        try {
            RelatedListController.updateRecords(null, 'Contact');
            System.assert(false, 'Should throw an exception for null records');
        } catch(AuraHandledException e) {
            // Expected exception
        }
        
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
            new List<String>()
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
            new List<String>()
        );
        
        Test.stopTest();
        
        System.assertEquals(50, result.records.size(), 'Should respect page size limit');
        System.assert(result.totalRecords > 200, 'Should handle large data sets');
    }
}