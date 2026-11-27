/**
 * @description Unit tests of the predicate builder: identifiers come from describe, operators from
 *              fixed maps, and user values never appear in the SOQL text (only bind names do).
 */
@IsTest
private class RelatedListQueryBuilderTest {
    private static final Id FAKE_ACCOUNT_ID = '001000000000000';

    private static RelatedListSchemaService.ResolvedList resolved() {
        return RelatedListSchemaService.resolve(RelatedListTestData.accountContacts(), FAKE_ACCOUNT_ID);
    }

    @IsTest
    static void parentScopeIsAlwaysFirstAndBound() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        qb.applySearch(null);
        qb.applyFilters(null, null);
        qb.applySort(null, null);
        String soql = qb.countQuery();
        Assert.isTrue(soql.startsWith('SELECT COUNT() FROM Contact WHERE AccountId = :arl0'), soql);
        Assert.areEqual(FAKE_ACCOUNT_ID, qb.getBinds().get('arl0'));
        Assert.isTrue(soql.endsWith('LIMIT 2001'), soql);
    }

    @IsTest
    static void userValuesNeverAppearInSoqlText() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        String evil = 'x\' OR Name != \'';
        qb.applySearch(evil);
        qb.applyFilters(
            new List<RelatedListController.FilterInput>{
                RelatedListTestData.filter('c_title', 'contains', evil),
                RelatedListTestData.filter('c_email', 'equals', evil)
            },
            'AND'
        );
        qb.applySort('c_title', 'desc');
        String soql = qb.pageQuery(new List<String>{ 'Id', 'Name' }, 10);
        Assert.isFalse(soql.contains('OR Name !='), soql);
        Assert.isFalse(soql.contains('\''), 'no quoted literals at all: ' + soql);
        Assert.isTrue(soql.contains('ORDER BY Title DESC NULLS LAST, Id ASC'), soql);
        Assert.isTrue(soql.endsWith('LIMIT 11'), 'one extra row detects more pages: ' + soql);
    }

    @IsTest
    static void likeEscapingIsLiteral() {
        Assert.areEqual('100\\%', RelatedListQueryBuilder.escapeLike('100%'));
        Assert.areEqual('a\\_b', RelatedListQueryBuilder.escapeLike('a_b'));
        Assert.areEqual('c\\\\d', RelatedListQueryBuilder.escapeLike('c\\d'));
    }

    @IsTest
    static void searchUsesOnlySearchableColumnsWithOneBind() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        qb.applySearch('  smith ');
        String soql = qb.countQuery();
        Assert.isTrue(soql.contains('(Name LIKE :arl1 OR Title LIKE :arl1 OR Email LIKE :arl1 OR Phone LIKE :arl1)'), soql);
        Assert.areEqual('%smith%', qb.getBinds().get('arl1'));
    }

    @IsTest
    static void orJoinIsParenthesised() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        qb.applyFilters(
            new List<RelatedListController.FilterInput>{
                RelatedListTestData.filter('c_title', 'startsWith', 'A'),
                RelatedListTestData.filter('c_email', 'isBlank', null)
            },
            'or'
        );
        String soql = qb.countQuery();
        Assert.isTrue(soql.contains('AND (Title LIKE :arl1 OR Email = null)'), soql);
    }

    @IsTest
    static void notContainsIncludesBlanks() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        qb.applyFilters(new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('c_title', 'notContains', 'vp') }, 'AND');
        Assert.isTrue(qb.countQuery().contains('(Title = null OR (NOT Title LIKE :arl1))'), qb.countQuery());
    }

    @IsTest
    static void dateValuesAreTyped() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        qb.applyFilters(new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('c_birth', 'lessOrEqual', '2000-02-29') }, 'AND');
        Assert.areEqual(Date.newInstance(2000, 2, 29), qb.getBinds().get('arl1'));
        Assert.isTrue(qb.countQuery().contains('Birthdate <= :arl1'), qb.countQuery());
    }

    @IsTest
    static void unknownOperatorIsRejected() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        try {
            qb.applyFilters(new List<RelatedListController.FilterInput>{ RelatedListTestData.filter('c_title', 'LIKE', 'x') }, 'AND');
            Assert.fail('raw SOQL operators are not accepted');
        } catch (RelatedListException e) {
            Assert.areEqual(RelatedListException.Category.INPUT, e.category);
        }
    }

    @IsTest
    static void fingerprintChangesWithQuery() {
        RelatedListQueryBuilder a = new RelatedListQueryBuilder(resolved());
        a.applySearch('x');
        a.applySort(null, null);
        RelatedListQueryBuilder b = new RelatedListQueryBuilder(resolved());
        b.applySearch('y');
        b.applySort(null, null);
        RelatedListQueryBuilder c = new RelatedListQueryBuilder(resolved());
        c.applySearch('x');
        c.applySort(null, null);
        Assert.areNotEqual(a.fingerprint(), b.fingerprint());
        Assert.areEqual(a.fingerprint(), c.fingerprint());
    }

    @IsTest
    static void keysetPredicateHandlesValuesAndNulls() {
        RelatedListSchemaService.ResolvedList rl = resolved();
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(rl);
        qb.applySort('c_title', 'asc');
        Contact withValue = new Contact(Id = '003000000000001', Title = 'CEO');
        qb.applyCursor(qb.encodeCursor(withValue));
        String soql = qb.pageQuery(new List<String>{ 'Id' }, 5);
        Assert.isTrue(soql.contains('(Title > :arl2 OR (Title = :arl2 AND Id > :arl1) OR Title = null)'), soql);

        RelatedListQueryBuilder qbNull = new RelatedListQueryBuilder(rl);
        qbNull.applySort('c_title', 'asc');
        qbNull.applyCursor(qbNull.encodeCursor(new Contact(Id = '003000000000002')));
        String soqlNull = qbNull.pageQuery(new List<String>{ 'Id' }, 5);
        Assert.isTrue(soqlNull.contains('(Title = null AND Id > :arl1)'), soqlNull);
    }

    @IsTest
    static void cursorForAnotherObjectIsStale() {
        RelatedListQueryBuilder qb = new RelatedListQueryBuilder(resolved());
        qb.applySort(null, null);
        String token = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'f' => qb.fingerprint(), 'i' => FAKE_ACCOUNT_ID })));
        try {
            qb.applyCursor(token);
            Assert.fail('cursor id must be a child row');
        } catch (RelatedListException e) {
            Assert.areEqual(RelatedListException.Category.STALE, e.category);
        }
    }

    @IsTest
    static void legacySplitKeepsOrderAndDropsBlanks() {
        Assert.areEqual(new List<String>{ 'Name', 'Email' }, RelatedListDefinitions.splitList(' Name , ,Email '));
        Assert.areEqual(0, RelatedListDefinitions.splitList(null).size());
    }

    @IsTest
    static void controllerStatusMapping() {
        Assert.areEqual(RelatedListController.STATUS_CONFIG, RelatedListController.statusFor(RelatedListException.config('x')));
        Assert.areEqual(RelatedListController.STATUS_ACCESS, RelatedListController.statusFor(RelatedListException.access('x')));
        Assert.areEqual(RelatedListController.STATUS_STALE, RelatedListController.statusFor(RelatedListException.stale()));
        Assert.areEqual(RelatedListController.STATUS_INPUT, RelatedListController.statusFor(RelatedListException.input('x')));
    }
}
