@IsTest
public class RelatedListControllerTest {
    @testSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account'
        );
        insert testAccount;
        
        // Create test contacts
        List<Contact> contacts = new List<Contact>();
        for(Integer i = 0; i < 5; i++) {
            contacts.add(new Contact(
                LastName = 'Test Contact ' + i,
                AccountId = testAccount.Id
            ));
        }
        insert contacts;
    }

    @IsTest
    static void testGetRecordsSuccess() {
        // Get test account
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            5,
            1
        );
        
        Test.stopTest();
        
        // Assertions
        System.assertEquals(5, result.totalRecords, 'Total records count should match');
        System.assertEquals(5, result.records.size(), 'Records returned should match page size');
        System.assert(result.records[0] instanceof Contact, 'Records should be of Contact type');
    }

    @IsTest
    static void testGetRecordsPagination() {
        // Get test account
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        RelatedListController.RelatedListWrapper result = RelatedListController.getRecords(
            'Contact',
            'AccountId',
            testAccount.Id,
            new List<String>{'LastName', 'Email'},
            2,  // pageSize = 2
            2   // pageNumber = 2 (second page)
        );
        
        Test.stopTest();
        
        // Assertions
        System.assertEquals(5, result.totalRecords, 'Total records count should match');
        System.assertEquals(2, result.records.size(), 'Records returned should match page size');
    }

    @IsTest
    static void testGetRecordsInvalidObject() {
        Test.startTest();
        
        try {
            RelatedListController.getRecords(
                'InvalidObject',
                'AccountId',
                '001000000000000',
                new List<String>{'Name'},
                5,
                1
            );
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            // Expected exception
            System.assert(e.getMessage().contains('Error'), 'Error message should be present');
        }
        
        Test.stopTest();
    }

    
    @IsTest
    static void testDeleteRecordSuccess() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        
        RelatedListController.deleteRecord(testContact.Id, 'Contact');
        
        Test.stopTest();
        
        // Verify deletion
        List<Contact> remainingContacts = [SELECT Id FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(0, remainingContacts.size(), 'Contact should have been deleted');
    }

    @IsTest
    static void testDeleteRecordInvalidId() {
        Test.startTest();
        
        try {
            RelatedListController.deleteRecord('', 'Contact');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Record ID cannot be blank'), 'Error message should match');
        }
        
        Test.stopTest();
    }

    @IsTest
    static void testDeleteRecordInvalidObject() {
        Test.startTest();
        
        try {
            RelatedListController.deleteRecord('001000000000000', 'InvalidObject');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Error'), 'Error message should be present');
        }
        
        Test.stopTest();
    }
}