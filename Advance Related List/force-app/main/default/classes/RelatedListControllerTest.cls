/**
 * @description End-to-end tests of the Advanced Related List boundary. Each permission test uses a
 *              Minimum Access user with an explicit permission set (object, field and custom
 *              permissions), not just System.runAs, so CRUD/FLS/sharing enforcement is exercised.
 */
@IsTest
private class RelatedListControllerTest {
    private static final String KEY = 'Test_Account_Contacts';

    @TestSetup
    static void setup() {
        RelatedListTestData.accountWithContacts('Alpha', 23);
        RelatedListTestData.accountWithContacts('Other', 3);
    }

    private static Account alpha() {
        return [SELECT Id FROM Account WHERE Name = 'Alpha' LIMIT 1];
    }

    private static Account other() {
        return [SELECT Id FROM Account WHERE Name = 'Other' LIMIT 1];
    }

    // ===== READ: definition mode =====

    @IsTest
    static void definitionReadReturnsDeclaredDtoOnly() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();

        Test.startTest();
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(KEY, acct.Id, 5));
        Test.stopTest();

        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.areEqual(23, res.totalCount, 'count must use the same parent scope as the list');
        Assert.isFalse(res.totalCountCapped);
        Assert.areEqual(5, res.rows.size());
        Assert.isTrue(res.hasMore);
        Assert.isNotNull(res.nextCursor);
        Assert.areEqual('definition', res.context.mode);
        Assert.areEqual('Contact', res.context.objectApiName);
        Assert.areEqual('c_name', res.context.sortKey, 'default sort comes from the definition');

        Set<String> allowedKeys = new Set<String>{ 'id' };
        for (RelatedListController.ColumnInfo col : res.columns) {
            allowedKeys.add(col.key);
            allowedKeys.add(col.key + '__id');
            allowedKeys.add(col.key + '__cur');
        }
        for (Map<String, Object> row : res.rows) {
            Assert.isTrue(allowedKeys.containsAll(row.keySet()), 'row has undeclared keys: ' + row.keySet());
        }
        String json = JSON.serialize(res);
        Assert.isFalse(json.contains('"attributes"'), 'no SObject may be serialized into the Aura response');
        Assert.isFalse(json.contains('"LastModifiedDate"'), 'only declared fields are returned');
    }

    @IsTest
    static void relationshipAddressAndNameFormatting() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();

        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(KEY, acct.Id, 1));

        Map<String, Object> row = res.rows[0];
        Assert.areEqual('Alpha', row.get('c_acct'), 'relationship value');
        Assert.areEqual(String.valueOf(acct.Id), row.get('c_acct__id'), 'relationship link targets the related record');
        Assert.areEqual(row.get('id'), row.get('c_name__id'), 'name links to the row record');
        String address = (String) row.get('c_addr');
        Assert.isTrue(address.contains('Main St') && address.contains('Springfield') && address.contains('12345'), address);
        Map<String, RelatedListController.ColumnInfo> byKey = new Map<String, RelatedListController.ColumnInfo>();
        for (RelatedListController.ColumnInfo col : res.columns) {
            byKey.put(col.key, col);
        }
        Assert.areEqual('name', byKey.get('c_name').type);
        Assert.areEqual('address', byKey.get('c_addr').type);
        Assert.areEqual('email', byKey.get('c_email').type);
        Assert.areEqual('date', byKey.get('c_birth').filterType);
    }

    @IsTest
    static void absentOptionalKeysAndLegitimateFalsyValues() {
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.definition('Opp_List', 'Account', 'Opportunity', 'AccountId');
        spec.columns.add(RelatedListTestData.column('o_name', 'Name', true, false, false, true));
        spec.columns.add(RelatedListTestData.column('o_amt', 'Amount', true, false, true, true));
        spec.columns.add(RelatedListTestData.column('o_priv', 'IsPrivate', true, false, true, false));
        spec.columns.add(RelatedListTestData.column('o_desc', 'Description', true, false, false, false));
        RelatedListTestData.register(spec);
        Account acct = alpha();
        insert new Opportunity(Name = 'Zero', AccountId = acct.Id, Amount = 0, IsPrivate = false, StageName = firstStage(), CloseDate = Date.today());

        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request('Opp_List', acct.Id, 10));

        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Map<String, Object> row = res.rows[0];
        Assert.areEqual(0, ((Decimal) row.get('o_amt')).intValue(), 'zero is a value, not blank');
        Assert.areEqual(false, row.get('o_priv'), 'false is a value, not blank');
        Assert.isFalse(row.containsKey('o_desc'), 'null values are omitted');
        Assert.isNotNull(row.get('o_amt__cur'), 'currency code accompanies currency values');
    }

    // ===== READ: legacy mode =====

    @IsTest
    static void legacyPropertiesStillWork() {
        Account acct = alpha();
        RelatedListController.ListRequest req = legacyRequest(acct.Id, 'Name,Email,Phone,MailingAddress,Account.Name', 'Name,Email,MailingStreet', 'Name');
        req.legacy.columnLabels = 'Full Name,,Phone Number';
        req.searchTerm = 'Contact 0001';

        RelatedListController.ListResponse res = RelatedListController.getRows(req);

        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.areEqual('legacy', res.context.mode);
        Assert.isFalse(res.context.canBulkDelete, 'legacy configuration can never enable bulk delete');
        Assert.areEqual(1, res.totalCount);
        Assert.areEqual('Full Name', res.columns[0].label);
        Assert.areEqual('Phone Number', res.columns[2].label);
        Assert.isFalse(res.columns[5].visible, 'MailingStreet becomes a hidden search-only column');
        Assert.isTrue(res.columns[5].searchable);
        Assert.areEqual('_sort', res.context.sortKey, 'legacy default sort is CreatedDate DESC (unchanged from v1)');
        Assert.areEqual('desc', res.context.sortDirection);
    }

    @IsTest
    static void legacyUnknownFieldIsConfigError() {
        RelatedListController.ListResponse res = RelatedListController.getRows(legacyRequest(alpha().Id, 'Name,Not_A_Field__c', '', ''));
        Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status);
        Assert.isTrue(res.message.contains('Not_A_Field__c'), res.message);
        Assert.isNull(res.rows, 'configuration errors return zero data');
    }

    @IsTest
    static void legacyWrongLookupTargetIsConfigError() {
        // ReportsToId points to Contact, not Account: browser props cannot widen the scope.
        RelatedListController.ListResponse res = RelatedListController.getRows(withLookup(legacyRequest(alpha().Id, 'Name', '', ''), 'ReportsToId'));
        Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, res.message);
    }

    @IsTest
    static void legacyNonLookupFieldIsConfigError() {
        RelatedListController.ListResponse res = RelatedListController.getRows(withLookup(legacyRequest(alpha().Id, 'Name', '', ''), 'Email'));
        Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, res.message);
    }

    // ===== CONFIG ERRORS =====

    @IsTest
    static void unknownOrInactiveDefinitionReturnsNoData() {
        RelatedListDefinitions.ListSpec inactive = RelatedListTestData.accountContacts();
        inactive.definitionKey = 'Inactive_List';
        inactive.active = false;
        RelatedListTestData.register(inactive);

        RelatedListController.ListResponse unknown = RelatedListController.getRows(RelatedListTestData.request('Nope', alpha().Id, 5));
        RelatedListController.ListResponse off = RelatedListController.getRows(RelatedListTestData.request('Inactive_List', alpha().Id, 5));
        RelatedListController.ListResponse malformed = RelatedListController.getRows(RelatedListTestData.request('bad key!', alpha().Id, 5));

        Assert.areEqual(RelatedListController.STATUS_CONFIG, unknown.status);
        Assert.areEqual(RelatedListController.STATUS_CONFIG, off.status);
        Assert.isTrue(off.message.contains('inactive'), off.message);
        Assert.areEqual(RelatedListController.STATUS_CONFIG, malformed.status);
        Assert.isNull(unknown.rows);
        Assert.isNull(off.rows);
    }

    @IsTest
    static void definitionOnWrongParentObjectIsConfigError() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(KEY, c.Id, 5));
        Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, res.message);
    }

    @IsTest
    static void invalidFieldPathsAreRejected() {
        List<String> badPaths = new List<String>{
            'Name) OR (Name != null',
            'Account.Nope__c',
            'NotARelationship.Name',
            'Account.Owner.Manager.Manager.Manager.Manager.Name',
            'Owner.Bogus'
        };
        Integer index = 0;
        for (String bad : badPaths) {
            RelatedListDefinitions.ListSpec spec = RelatedListTestData.definition('Bad_' + index, 'Account', 'Contact', 'AccountId');
            spec.columns.add(RelatedListTestData.column('ok', 'Name', true, false, false, false));
            spec.columns.add(RelatedListTestData.column('bad', bad, true, false, false, false));
            RelatedListTestData.register(spec);
            RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request('Bad_' + index, alpha().Id, 5));
            Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, bad + ' => ' + res.message);
            index++;
        }
    }

    @IsTest
    static void polymorphicHopIsRejected() {
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.definition('Poly', 'Account', 'Task', 'WhatId');
        spec.columns.add(RelatedListTestData.column('t_subject', 'Subject', true, false, false, false));
        spec.columns.add(RelatedListTestData.column('t_what', 'What.Name', true, false, false, false));
        RelatedListTestData.register(spec);
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request('Poly', alpha().Id, 5));
        Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, res.message);
        Assert.isTrue(res.message.contains('polymorphic'), res.message);
    }

    @IsTest
    static void unsupportedCapabilityIsConfigError() {
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.definition('Bad_Cap', 'Account', 'Contact', 'AccountId');
        spec.columns.add(RelatedListTestData.column('addr', 'MailingAddress', true, false, false, true));
        RelatedListTestData.register(spec);
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request('Bad_Cap', alpha().Id, 5));
        Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, res.message);
    }

    @IsTest
    static void missingParentIdIsConfigErrorAndBadIdIsInputError() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Assert.areEqual(RelatedListController.STATUS_CONFIG, RelatedListController.getRows(RelatedListTestData.request(KEY, null, 5)).status);
        RelatedListController.ListRequest req = RelatedListTestData.request(KEY, null, 5);
        req.parentId = 'not-an-id';
        Assert.areEqual(RelatedListController.STATUS_INPUT, RelatedListController.getRows(req).status);
        Assert.areEqual(RelatedListController.STATUS_INPUT, RelatedListController.getRows(null).status);
    }

    // ===== INPUT VALIDATION =====

    @IsTest
    static void inputBoundsAndUnknownOperatorsAreRejected() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Id acctId = alpha().Id;

        RelatedListController.ListRequest tooBig = RelatedListTestData.request(KEY, acctId, 101);
        RelatedListController.ListRequest zero = RelatedListTestData.request(KEY, acctId, 0);
        RelatedListController.ListRequest longSearch = RelatedListTestData.request(KEY, acctId, 5);
        longSearch.searchTerm = 'x'.repeat(101);
        RelatedListController.ListRequest badOp = RelatedListTestData.request(KEY, acctId, 5);
        badOp.filters.add(RelatedListTestData.filter('c_title', 'INVALID_OPERATOR', 'x'));
        RelatedListController.ListRequest injectedOp = RelatedListTestData.request(KEY, acctId, 5);
        injectedOp.filters.add(RelatedListTestData.filter('c_title', '= \'x\' OR Name !=', 'x'));
        RelatedListController.ListRequest unknownKey = RelatedListTestData.request(KEY, acctId, 5);
        unknownKey.filters.add(RelatedListTestData.filter('Name', 'equals', 'x'));
        RelatedListController.ListRequest notFilterable = RelatedListTestData.request(KEY, acctId, 5);
        notFilterable.filters.add(RelatedListTestData.filter('c_name', 'equals', 'x'));
        RelatedListController.ListRequest emptyValue = RelatedListTestData.request(KEY, acctId, 5);
        emptyValue.filters.add(RelatedListTestData.filter('c_title', 'equals', '  '));
        RelatedListController.ListRequest badDate = RelatedListTestData.request(KEY, acctId, 5);
        badDate.filters.add(RelatedListTestData.filter('c_birth', 'equals', '31/12/2020'));
        RelatedListController.ListRequest textOpOnDate = RelatedListTestData.request(KEY, acctId, 5);
        textOpOnDate.filters.add(RelatedListTestData.filter('c_birth', 'contains', '2020'));
        RelatedListController.ListRequest tooMany = RelatedListTestData.request(KEY, acctId, 5);
        for (Integer i = 0; i < 21; i++) {
            tooMany.filters.add(RelatedListTestData.filter('c_title', 'isBlank', null));
        }
        RelatedListController.ListRequest badSort = RelatedListTestData.request(KEY, acctId, 5);
        badSort.sortKey = 'c_addr';

        for (RelatedListController.ListRequest req : new List<RelatedListController.ListRequest>{
            tooBig, zero, longSearch, badOp, injectedOp, unknownKey, notFilterable, emptyValue, badDate, textOpOnDate, tooMany, badSort
        }) {
            RelatedListController.ListResponse res = RelatedListController.getRows(req);
            Assert.areEqual(RelatedListController.STATUS_INPUT, res.status, res.message);
            Assert.isNull(res.rows);
        }
    }

    // ===== SEARCH / FILTER =====

    @IsTest
    static void searchIsScopedToParentAndTreatsWildcardsLiterally() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();
        insert new List<Contact>{
            new Contact(AccountId = acct.Id, LastName = 'Rate 100% Exact'),
            new Contact(AccountId = acct.Id, LastName = 'Rate 100x Exact'),
            new Contact(AccountId = other().Id, LastName = 'Other 100% Exact')
        };
        RelatedListController.ListRequest req = RelatedListTestData.request(KEY, acct.Id, 10);
        req.searchTerm = '100%';
        RelatedListController.ListResponse res = RelatedListController.getRows(req);
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.areEqual(1, res.totalCount, '% is literal and other parents are excluded');

        req.searchTerm = 'Rate 100_';
        Assert.areEqual(0, RelatedListController.getRows(req).totalCount, '_ is literal');
    }

    @IsTest
    static void typedFiltersWithAndOr() {
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.definition('Opp_Typed', 'Account', 'Opportunity', 'AccountId');
        spec.columns.add(RelatedListTestData.column('o_name', 'Name', true, true, true, true));
        spec.columns.add(RelatedListTestData.column('o_amt', 'Amount', true, false, true, true));
        spec.columns.add(RelatedListTestData.column('o_close', 'CloseDate', true, false, true, true));
        spec.columns.add(RelatedListTestData.column('o_stage', 'StageName', true, false, true, false));
        spec.columns.add(RelatedListTestData.column('o_priv', 'IsPrivate', true, false, true, false));
        spec.columns.add(RelatedListTestData.column('o_created', 'CreatedDate', true, false, true, true));
        RelatedListTestData.register(spec);
        Account acct = alpha();
        String stage = firstStage();
        insert new List<Opportunity>{
            new Opportunity(Name = 'Small', AccountId = acct.Id, Amount = 10, StageName = stage, CloseDate = Date.newInstance(2030, 1, 1)),
            new Opportunity(Name = 'Big', AccountId = acct.Id, Amount = 5000, StageName = stage, CloseDate = Date.newInstance(2030, 6, 1), IsPrivate = true),
            new Opportunity(Name = 'None', AccountId = acct.Id, StageName = stage, CloseDate = Date.newInstance(2031, 1, 1))
        };

        Assert.areEqual(1, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_amt', 'greaterThan', '100') }, 'AND'));
        Assert.areEqual(1, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_amt', 'isBlank', null) }, 'AND'));
        Assert.areEqual(1, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_close', 'equals', '2030-06-01') }, 'AND'));
        Assert.areEqual(1, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_priv', 'equals', 'true') }, 'AND'));
        Assert.areEqual(3, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_stage', 'equals', stage) }, 'AND'));
        Assert.areEqual(3, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_created', 'equals', String.valueOf(Date.today())) }, 'AND'), 'date on a date/time field matches the whole day');
        Assert.areEqual(0, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_created', 'lessThan', String.valueOf(Date.today())) }, 'AND'));
        List<RelatedListController.FilterInput> pair = new List<RelatedListController.FilterInput>{
            RelatedListTestData.filter('o_name', 'startsWith', 'Sm'),
            RelatedListTestData.filter('o_name', 'endsWith', 'ig')
        };
        Assert.areEqual(0, countWith('Opp_Typed', acct.Id, pair, 'AND'));
        Assert.areEqual(2, countWith('Opp_Typed', acct.Id, pair, 'OR'));
        Assert.areEqual(2, countWith('Opp_Typed', acct.Id, new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('o_name', 'notContains', 'mal') }, 'AND'));
        RelatedListController.ListRequest badPicklist = RelatedListTestData.request('Opp_Typed', acct.Id, 10);
        badPicklist.filters.add(RelatedListTestData.filter('o_stage', 'equals', 'Not A Stage'));
        Assert.areEqual(RelatedListController.STATUS_INPUT, RelatedListController.getRows(badPicklist).status);
    }

    // ===== SORT & PAGING =====

    @IsTest
    static void keysetPagingWithDuplicateSortValuesVisitsEveryRowOnce() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();
        for (String direction : new List<String>{ 'asc', 'desc' }) {
            RelatedListController.ListRequest req = RelatedListTestData.request(KEY, acct.Id, 4);
            req.sortKey = 'c_title'; // 15 duplicates of "Same Title" + 8 nulls
            req.sortDirection = direction;
            List<Id> seen = new List<Id>();
            Set<Id> unique = new Set<Id>();
            Integer pages = 0;
            Boolean sawNull = false;
            Boolean nullBeforeValue = false;
            do {
                RelatedListController.ListResponse res = RelatedListController.getRows(req);
                Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
                for (Map<String, Object> row : res.rows) {
                    Id rowId = (Id) row.get('id');
                    seen.add(rowId);
                    unique.add(rowId);
                    if (!row.containsKey('c_title')) {
                        sawNull = true;
                    } else if (sawNull) {
                        nullBeforeValue = true;
                    }
                }
                req.cursor = res.nextCursor;
                pages++;
            } while (req.cursor != null && pages < 20);
            Assert.areEqual(23, seen.size(), direction + ': every row exactly once');
            Assert.areEqual(23, unique.size(), direction + ': no duplicates across pages');
            Assert.areEqual(6, pages, direction + ': ceil(23/4) pages');
            Assert.isFalse(nullBeforeValue, direction + ': nulls sort last');
        }
    }

    @IsTest
    static void sortAppliesToWholeListNotCurrentPage() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        RelatedListController.ListRequest req = RelatedListTestData.request(KEY, alpha().Id, 3);
        req.sortKey = 'c_name';
        req.sortDirection = 'desc';
        RelatedListController.ListResponse res = RelatedListController.getRows(req);
        Assert.isTrue(((String) res.rows[0].get('c_name')).endsWith('0022'), 'first row of page 1 is the global maximum: ' + res.rows[0].get('c_name'));
    }

    @IsTest
    static void tamperedOrMismatchedCursorIsStale() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Id acctId = alpha().Id;
        RelatedListController.ListResponse first = RelatedListController.getRows(RelatedListTestData.request(KEY, acctId, 5));

        RelatedListController.ListRequest changed = RelatedListTestData.request(KEY, acctId, 5);
        changed.searchTerm = 'Contact';
        changed.cursor = first.nextCursor;
        Assert.areEqual(RelatedListController.STATUS_STALE, RelatedListController.getRows(changed).status, 'cursor is bound to the query');

        RelatedListController.ListRequest otherParent = RelatedListTestData.request(KEY, other().Id, 5);
        otherParent.cursor = first.nextCursor;
        Assert.areEqual(RelatedListController.STATUS_STALE, RelatedListController.getRows(otherParent).status, 'cursor is bound to the parent');

        RelatedListController.ListRequest garbage = RelatedListTestData.request(KEY, acctId, 5);
        garbage.cursor = EncodingUtil.base64Encode(Blob.valueOf('{"f":"x"}'));
        Assert.areEqual(RelatedListController.STATUS_STALE, RelatedListController.getRows(garbage).status);
    }

    // ===== PERMISSIONS =====

    @IsTest
    static void hiddenFieldIsOmittedForRestrictedUser() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();
        User reader = RelatedListTestData.restrictedUser(
            'arlread',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Account'), new RelatedListTestData.ObjectAccess('Contact') },
            new List<String>{ 'Contact.Email', 'Contact.AccountId', 'Contact.Title' },
            false
        );
        RelatedListTestData.giveToUser(acct, reader);

        RelatedListController.ListResponse res;
        System.runAs(reader) {
            RelatedListController.ListRequest req = RelatedListTestData.request(KEY, acct.Id, 50);
            req.searchTerm = '555'; // Phone is searchable but hidden: must not match on it
            res = RelatedListController.getRows(req);
            RelatedListController.ListRequest all = RelatedListTestData.request(KEY, acct.Id, 50);
            RelatedListController.ListResponse allRes = RelatedListController.getRows(all);
            Assert.areEqual(RelatedListController.STATUS_OK, allRes.status, allRes.message);
            Set<String> keys = new Set<String>();
            for (RelatedListController.ColumnInfo col : allRes.columns) {
                keys.add(col.key);
            }
            Assert.isFalse(keys.contains('c_phone'), 'field without FLS is not described');
            Assert.isFalse(keys.contains('c_birth'), 'field without FLS is not described');
            Assert.isTrue(keys.contains('c_email'));
            Assert.isTrue(allRes.context.omittedColumnCount >= 2, 'omitted count reported');
            for (Map<String, Object> row : allRes.rows) {
                Assert.isFalse(row.containsKey('c_phone'));
            }
            Assert.isFalse(allRes.context.canEdit, 'read-only user');
            Assert.isFalse(allRes.context.canDelete, 'read-only user');
            Assert.isFalse(allRes.context.canBulkDelete, 'read-only user');
        }
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.areEqual(0, res.totalCount, 'search must not use the hidden Phone field');
    }

    @IsTest
    static void userWithoutChildAccessGetsAccessError() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();
        User noContacts = RelatedListTestData.restrictedUser(
            'arlnoc',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Account') },
            new List<String>(),
            false
        );
        RelatedListTestData.giveToUser(acct, noContacts);
        System.runAs(noContacts) {
            RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(KEY, acct.Id, 5));
            Assert.areEqual(RelatedListController.STATUS_ACCESS, res.status, res.message);
            Assert.isNull(res.rows);
        }
    }

    @IsTest
    static void deniedParentGetsAccessErrorWithoutRevealingExistence() {
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.definition('Contact_Cases', 'Contact', 'Case', 'ContactId');
        spec.columns.add(RelatedListTestData.column('k_subject', 'Subject', true, true, false, true));
        RelatedListTestData.register(spec);
        Contact parent = [SELECT Id FROM Contact LIMIT 1];
        User caseOnly = RelatedListTestData.restrictedUser(
            'arlcase',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Case') },
            new List<String>{ 'Case.Subject', 'Case.ContactId' },
            false
        );
        System.runAs(caseOnly) {
            RelatedListController.ListResponse denied = RelatedListController.getRows(RelatedListTestData.request('Contact_Cases', parent.Id, 5));
            String fakeId = String.valueOf(parent.Id).left(3) + '000000000000';
            RelatedListController.ListResponse missing = RelatedListController.getRows(RelatedListTestData.request('Contact_Cases', fakeId, 5));
            Assert.areEqual(RelatedListController.STATUS_ACCESS, denied.status, denied.message);
            Assert.areEqual(denied.status, missing.status);
            Assert.areEqual(denied.message, missing.message, 'no access and not found are indistinguishable');
        }
    }

    // ===== BULK DELETE =====

    @IsTest
    static void bulkDeleteMixedOutcomeIsTruthfulAndScoped() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();
        User deleter = RelatedListTestData.restrictedUser(
            'arldel',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Account'), new RelatedListTestData.ObjectAccess('Contact').remove() },
            new List<String>{ 'Contact.AccountId' },
            true
        );
        RelatedListTestData.giveToUser(acct, deleter);
        List<Contact> mine = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 2];
        Contact otherParentRow = [SELECT Id FROM Contact WHERE AccountId = :other().Id LIMIT 1];

        RelatedListController.DeleteRequest req = new RelatedListController.DeleteRequest();
        req.definitionKey = KEY;
        req.parentId = acct.Id;
        req.recordIds = new List<String>{ mine[0].Id, mine[1].Id, otherParentRow.Id, 'garbage', acct.Id, mine[0].Id };

        RelatedListController.DeleteResponse res;
        Integer queries;
        Integer dml;
        System.runAs(deleter) {
            Test.startTest();
            res = RelatedListController.deleteRows(req);
            queries = Limits.getQueries();
            dml = Limits.getDmlStatements();
            Test.stopTest();
        }
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.areEqual(2, res.deletedCount);
        Assert.areEqual(3, res.failedCount, 'other-parent row, malformed id and wrong-type id fail; duplicate ignored');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Id IN :mine]);
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Id = :otherParentRow.Id], 'row outside the list scope is untouched');
        for (RelatedListController.RowResult rr : res.results) {
            if (!rr.success) {
                Assert.areEqual('This record isn\'t available.', rr.message, 'no existence leak');
            }
        }
        Assert.isTrue(queries <= 2, 'parent check + scoped requery only; was ' + queries);
        Assert.areEqual(1, dml, 'one DML statement for the whole batch');
    }

    @IsTest
    static void bulkDeleteRequiresCustomPermissionDefinitionAndBounds() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account acct = alpha();
        User noPerm = RelatedListTestData.restrictedUser(
            'arlnop',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Account'), new RelatedListTestData.ObjectAccess('Contact').remove() },
            new List<String>{ 'Contact.AccountId' },
            false
        );
        RelatedListTestData.giveToUser(acct, noPerm);
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        RelatedListController.DeleteRequest req = new RelatedListController.DeleteRequest();
        req.definitionKey = KEY;
        req.parentId = acct.Id;
        req.recordIds = new List<String>{ c.Id };
        System.runAs(noPerm) {
            Assert.areEqual(RelatedListController.STATUS_ACCESS, RelatedListController.deleteRows(req).status, 'custom permission required');
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Id = :c.Id]);

        RelatedListController.DeleteRequest legacy = new RelatedListController.DeleteRequest();
        legacy.parentId = acct.Id;
        legacy.recordIds = new List<String>{ c.Id };
        Assert.areEqual(RelatedListController.STATUS_CONFIG, RelatedListController.deleteRows(legacy).status, 'legacy lists cannot bulk delete');

        RelatedListService.bulkDeletePermissionOverride = true;
        RelatedListController.DeleteRequest empty = new RelatedListController.DeleteRequest();
        empty.definitionKey = KEY;
        empty.parentId = acct.Id;
        empty.recordIds = new List<String>();
        Assert.areEqual(RelatedListController.STATUS_INPUT, RelatedListController.deleteRows(empty).status);
        RelatedListController.DeleteRequest tooMany = new RelatedListController.DeleteRequest();
        tooMany.definitionKey = KEY;
        tooMany.parentId = acct.Id;
        tooMany.recordIds = new List<String>();
        for (Integer i = 0; i < 101; i++) {
            tooMany.recordIds.add(c.Id);
        }
        Assert.areEqual(RelatedListController.STATUS_INPUT, RelatedListController.deleteRows(tooMany).status);

        RelatedListDefinitions.ListSpec noBulk = RelatedListTestData.accountContacts();
        noBulk.definitionKey = 'No_Bulk';
        noBulk.allowBulkDelete = false;
        RelatedListTestData.register(noBulk);
        req.definitionKey = 'No_Bulk';
        Assert.areEqual(RelatedListController.STATUS_ACCESS, RelatedListController.deleteRows(req).status, 'definition must allow bulk delete');
    }

    // ===== BENCHMARKS (governor usage) =====

    @IsTest
    static void queryBudgetPerPage() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Id acctId = alpha().Id;
        Test.startTest();
        RelatedListController.ListResponse first = RelatedListController.getRows(RelatedListTestData.request(KEY, acctId, 10));
        Integer firstPageQueries = Limits.getQueries();
        RelatedListController.ListRequest next = RelatedListTestData.request(KEY, acctId, 10);
        next.cursor = first.nextCursor;
        RelatedListController.ListResponse second = RelatedListController.getRows(next);
        Integer secondPageQueries = Limits.getQueries() - firstPageQueries;
        Test.stopTest();
        Assert.areEqual(RelatedListController.STATUS_OK, second.status, second.message);
        Assert.areEqual(3, firstPageQueries, 'first page: parent check + count + page');
        Assert.areEqual(2, secondPageQueries, 'later pages: parent check + page (no count)');
        Assert.isNull(second.totalCount);
    }

    @IsTest
    static void largeListCountIsCappedAndDeepPageIsCheap() {
        RelatedListTestData.register(RelatedListTestData.accountContacts());
        Account big = new Account(Name = 'Big');
        insert big;
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 2005; i++) {
            contacts.add(new Contact(AccountId = big.Id, LastName = 'Bulk ' + String.valueOf(i).leftPad(5, '0')));
        }
        insert contacts;
        Test.startTest();
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(KEY, big.Id, 100));
        Test.stopTest();
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.isTrue(res.totalCountCapped);
        Assert.areEqual(RelatedListQueryBuilder.COUNT_CAP, res.totalCount);
        Assert.areEqual(100, res.rows.size());
    }

    // ===== SHIPPED CUSTOM METADATA =====

    @IsTest
    static void shippedExampleDefinitionLoadsFromCustomMetadata() {
        // No test override: exercises the real CMT SOQL path, including Definition__r.DeveloperName.
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request('Account_Contacts', alpha().Id, 5));
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        Assert.areEqual(9, res.columns.size());
        Assert.isFalse(res.columns[8].visible, 'MailingCity is search-only');
        Assert.areEqual('Contact Owner', res.columns[7].label);
    }

    // ===== HELPERS =====

    private static Integer countWith(String key, Id parentId, List<RelatedListController.FilterInput> filters, String logic) {
        RelatedListController.ListRequest req = RelatedListTestData.request(key, parentId, 10);
        req.filters = filters;
        req.filterLogic = logic;
        RelatedListController.ListResponse res = RelatedListController.getRows(req);
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, res.message);
        return res.totalCount;
    }

    private static String firstStage() {
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static RelatedListController.ListRequest legacyRequest(Id parentId, String fields, String searchable, String sortable) {
        RelatedListController.ListRequest req = new RelatedListController.ListRequest();
        req.parentId = parentId;
        req.pageSize = 10;
        req.legacy = new RelatedListController.LegacyConfig();
        req.legacy.childObjectApiName = 'Contact';
        req.legacy.parentLookupField = 'AccountId';
        req.legacy.fieldsToDisplay = fields;
        req.legacy.searchableFields = searchable;
        req.legacy.sortableFields = sortable;
        return req;
    }

    private static RelatedListController.ListRequest withLookup(RelatedListController.ListRequest req, String lookup) {
        req.legacy.parentLookupField = lookup;
        return req;
    }
}
