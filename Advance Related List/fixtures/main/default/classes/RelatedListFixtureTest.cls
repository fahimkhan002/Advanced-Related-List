/**
 * @description Sandbox-only verification with custom-object fixtures (fixtures/ package directory).
 *              Proves: two lookups from one child to the same parent type stay distinct; a custom
 *              parent -> custom child relationship works through the deployed Custom Metadata; and
 *              the response for custom objects contains only declared keys (no SObject payload).
 *              Never deploy fixtures/ to production.
 */
@IsTest
private class RelatedListFixtureTest {
    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Fixture A');
        Account b = new Account(Name = 'Fixture B');
        insert new List<Account>{ a, b };
        ARL_Fixture_Parent__c parent = new ARL_Fixture_Parent__c(Name = 'Custom Parent');
        insert parent;
        insert new List<ARL_Fixture_Child__c>{
            new ARL_Fixture_Child__c(Name = 'Primary only', Primary_Account__c = a.Id, Secondary_Account__c = b.Id, Fixture_Parent__c = parent.Id, Amount__c = 0, Score__c = 5, Is_Open__c = false, Due_Date__c = Date.newInstance(2030, 1, 1)),
            new ARL_Fixture_Child__c(Name = 'Both A', Primary_Account__c = a.Id, Secondary_Account__c = a.Id, Fixture_Parent__c = parent.Id, Amount__c = 25.5, Score__c = 5, Is_Open__c = true),
            new ARL_Fixture_Child__c(Name = 'Secondary only', Primary_Account__c = b.Id, Secondary_Account__c = a.Id, Score__c = 9)
        };
    }

    private static Account fixtureAccount(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1];
    }

    private static Set<String> names(RelatedListController.ListResponse res) {
        Set<String> result = new Set<String>();
        for (Map<String, Object> row : res.rows) {
            result.add((String) row.get('FXP_Name') != null ? (String) row.get('FXP_Name') : (String) row.get('FXS_Name'));
        }
        return result;
    }

    @IsTest
    static void twoLookupsToSameParentStayDistinct() {
        Id accountA = fixtureAccount('Fixture A').Id;
        RelatedListController.ListResponse primary = RelatedListController.getRows(RelatedListTestData.request('ARL_Fixture_Primary', accountA, 10));
        RelatedListController.ListResponse secondary = RelatedListController.getRows(RelatedListTestData.request('ARL_Fixture_Secondary', accountA, 10));
        Assert.areEqual(RelatedListController.STATUS_OK, primary.status, 'message: ' + primary.message);
        Assert.areEqual(RelatedListController.STATUS_OK, secondary.status, 'message: ' + secondary.message);
        Assert.areEqual(new Set<String>{ 'Primary only', 'Both A' }, names(primary));
        Assert.areEqual(new Set<String>{ 'Both A', 'Secondary only' }, names(secondary));
    }

    @IsTest
    static void bulkDeleteRespectsTheSelectedLookup() {
        Id accountA = fixtureAccount('Fixture A').Id;
        ARL_Fixture_Child__c secondaryOnly = [SELECT Id FROM ARL_Fixture_Child__c WHERE Name = 'Secondary only' LIMIT 1];
        RelatedListService.bulkDeletePermissionOverride = true;
        RelatedListController.DeleteRequest req = new RelatedListController.DeleteRequest();
        req.definitionKey = 'ARL_Fixture_Primary';
        req.parentId = accountA;
        req.recordIds = new List<String>{ secondaryOnly.Id };
        RelatedListController.DeleteResponse res = RelatedListController.deleteRows(req);
        Assert.areEqual(0, res.deletedCount, 'row linked to A only through the other lookup is out of scope');
        Assert.areEqual(1, [SELECT COUNT() FROM ARL_Fixture_Child__c WHERE Id = :secondaryOnly.Id]);
    }

    @IsTest
    static void customParentRelationshipAndTypedValues() {
        ARL_Fixture_Parent__c parent = [SELECT Id FROM ARL_Fixture_Parent__c LIMIT 1];
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request('ARL_Fixture_Custom_Parent', parent.Id, 10));
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, 'message: ' + res.message);
        Assert.areEqual(2, res.totalCount);
        Map<String, Object> first = res.rows[0]; // Due_Date__c ASC NULLS LAST => 'Primary only' first
        Assert.areEqual('Primary only', first.get('FXC_Name'));
        Assert.areEqual(0, ((Decimal) first.get('FXC_Amount')).intValue(), 'zero kept');
        Assert.areEqual(false, first.get('FXC_Is_Open'), 'false kept');
        Assert.areEqual('Custom Parent', first.get('FXC_Parent_Name'), 'custom relationship path');
        Assert.areEqual(String.valueOf(parent.Id), first.get('FXC_Parent_Name__id'));
        Assert.isFalse(res.rows[1].containsKey('FXC_Due_Date'), 'absent optional key');
        String json = JSON.serialize(res);
        Assert.isFalse(json.contains('"attributes"'), 'no SObject in the Aura response');
        Assert.isFalse(json.contains('SystemModstamp'), 'no undeclared system fields');
    }

    @IsTest
    static void typedFiltersOnCustomFields() {
        ARL_Fixture_Parent__c parent = [SELECT Id FROM ARL_Fixture_Parent__c LIMIT 1];
        RelatedListController.ListRequest req = RelatedListTestData.request('ARL_Fixture_Custom_Parent', parent.Id, 10);
        req.filters.add(RelatedListTestData.filter('FXC_Amount', 'greaterThan', '1'));
        req.filters.add(RelatedListTestData.filter('FXC_Is_Open', 'equals', 'true'));
        RelatedListController.ListResponse res = RelatedListController.getRows(req);
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, 'message: ' + res.message);
        Assert.areEqual(1, res.totalCount);
    }
}
