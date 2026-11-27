/**
 * @description Tests for configurable list actions (any number of screen flows and quick actions,
 *              in the list header or each row): runtime loading and filtering, legacy single-Flow
 *              migration, and the builder's validation and save of action records.
 */
@IsTest
private class RelatedListActionsTest {
    private class CapturingDeployer implements RelatedListBuilderService.Deployer {
        public Metadata.DeployContainer captured;
        public Id deploy(Metadata.DeployContainer container) {
            captured = container;
            return Id.valueOf('0Af000000000001');
        }
    }

    private static RelatedListDefinitions.ActionSpec action(String key, String type, String target, String placement) {
        RelatedListDefinitions.ActionSpec a = new RelatedListDefinitions.ActionSpec();
        a.key = key;
        a.actionType = type;
        a.target = target;
        a.placement = placement;
        return a;
    }

    private static RelatedListController.ListContext contextFor(RelatedListDefinitions.ListSpec spec, Id parentId) {
        RelatedListTestData.register(spec);
        RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(spec.definitionKey, parentId, 5));
        Assert.areEqual(RelatedListController.STATUS_OK, res.status, 'message: ' + res.message);
        return res.context;
    }

    // ===== RUNTIME =====

    @IsTest
    static void multipleFlowsAndQuickActionsAreReturnedInOrder() {
        Account acct = RelatedListTestData.accountWithContacts('Actions', 2);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        spec.actions.add(action('a1', 'Flow', 'First_Flow', 'List'));
        spec.actions.add(action('a2', 'Flow', 'Second_Flow', 'List'));
        spec.actions.add(action('a3', 'Flow', 'Third_Flow', 'Row'));
        spec.actions.add(action('a4', 'Quick_Action', 'NewTask', 'List'));
        spec.actions.add(action('a5', 'Quick_Action', 'LogACall', 'Row'));
        RelatedListDefinitions.ActionSpec labelled = action('a6', 'Quick_Action', 'NewTask', 'Row');
        labelled.label = 'Follow up';
        spec.actions.add(labelled);

        RelatedListController.ListContext ctx = contextFor(spec, acct.Id);
        List<String> keys = new List<String>();
        Map<String, RelatedListController.ActionInfo> byKey = new Map<String, RelatedListController.ActionInfo>();
        for (RelatedListController.ActionInfo a : ctx.actions) {
            keys.add(a.key);
            byKey.put(a.key, a);
        }
        Assert.areEqual(new List<String>{ 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'new' }, keys, 'all configured actions in order; New is appended for lists without a New row');
        Assert.areEqual('flow', byKey.get('a1').type);
        Assert.areEqual('list', byKey.get('a1').placement);
        Assert.areEqual('row', byKey.get('a3').placement);
        Assert.areEqual('quickAction', byKey.get('a4').type);
        Assert.areEqual('Global.NewTask', byKey.get('a4').target, 'global actions are navigated as Global.<name>');
        Assert.isNotNull(byKey.get('a4').label, 'quick actions default to their Salesforce label');
        Assert.areEqual('Follow up', byKey.get('a6').label, 'admin label wins');
    }

    @IsTest
    static void unlabelledFlowsUseTheFlowLabelButLegacyFlowKeepsThePageTitle() {
        List<FlowDefinitionView> flows = [SELECT ApiName, Label FROM FlowDefinitionView WHERE ProcessType = 'Flow' AND IsActive = TRUE LIMIT 1];
        if (flows.isEmpty()) {
            return; // no active screen flow in this org to label from; behaviour covered by the client fallback
        }
        Account acct = RelatedListTestData.accountWithContacts('Labels', 1);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        spec.flowApiName = 'Some_Legacy_Flow';
        spec.actions.add(action('configured', 'Flow', flows[0].ApiName, 'List'));
        RelatedListController.ListContext ctx = contextFor(spec, acct.Id);
        Map<String, RelatedListController.ActionInfo> byKey = new Map<String, RelatedListController.ActionInfo>();
        for (RelatedListController.ActionInfo a : ctx.actions) {
            byKey.put(a.key, a);
        }
        Assert.areEqual(flows[0].Label, byKey.get('configured').label);
        Assert.isNull(byKey.get('flow').label, 'legacy flow keeps the page Flow Modal Title');
    }

    @IsTest
    static void unavailableQuickActionsAreNotOffered() {
        Account acct = RelatedListTestData.accountWithContacts('Unavailable', 1);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        spec.actions.add(action('ok', 'Flow', 'Some_Flow', 'List'));
        spec.actions.add(action('missing', 'Quick_Action', 'Contact.Does_Not_Exist', 'Row'));
        RelatedListController.ListContext ctx = contextFor(spec, acct.Id);
        Assert.areEqual(2, ctx.actions.size(), 'a broken button is never shown (ok + New)');
        Assert.areEqual('ok', ctx.actions[0].key);
        Assert.areEqual('new', ctx.actions[1].key);
    }

    @IsTest
    static void legacySingleFlowBecomesAHeaderActionWithTheV1Rule() {
        Account acct = RelatedListTestData.accountWithContacts('Legacy', 1);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        spec.flowApiName = 'Old_Flow';
        RelatedListController.ListContext ctx = contextFor(spec, acct.Id);
        Assert.areEqual(2, ctx.actions.size(), 'legacy flow + New');
        Assert.areEqual('flow', ctx.actions[0].key);
        Assert.areEqual('Old_Flow', ctx.actions[0].target);
        Assert.isNull(ctx.actions[0].label, 'the page Flow Modal Title is used for the legacy flow');

        // A configured action for the same flow replaces the legacy one (no duplicate button).
        RelatedListDefinitions.ListSpec both = RelatedListTestData.accountContacts();
        both.definitionKey = 'Both';
        both.flowApiName = 'Old_Flow';
        both.actions.add(action('configured', 'Flow', 'Old_Flow', 'List'));
        RelatedListController.ListContext ctx2 = contextFor(both, acct.Id);
        Assert.areEqual(2, ctx2.actions.size(), 'configured flow + New, no duplicate legacy flow');
        Assert.areEqual('configured', ctx2.actions[0].key);

        // Legacy App Builder flowName works the same way.
        RelatedListController.ListRequest req = new RelatedListController.ListRequest();
        req.parentId = acct.Id;
        req.pageSize = 5;
        req.legacy = new RelatedListController.LegacyConfig();
        req.legacy.childObjectApiName = 'Contact';
        req.legacy.parentLookupField = 'AccountId';
        req.legacy.fieldsToDisplay = 'Name';
        req.legacy.flowName = 'Legacy_Page_Flow';
        RelatedListController.ListResponse res = RelatedListController.getRows(req);
        Assert.areEqual('Legacy_Page_Flow', res.context.actions[0].target);
    }

    @IsTest
    static void legacyFlowStillNeedsEditAccessButConfiguredFlowsDoNot() {
        Account acct = RelatedListTestData.accountWithContacts('ReadOnly', 1);
        User reader = RelatedListTestData.restrictedUser(
            'arlact',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Account'), new RelatedListTestData.ObjectAccess('Contact') },
            new List<String>{ 'Contact.AccountId' },
            false
        );
        RelatedListTestData.giveToUser(acct, reader);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        spec.flowApiName = 'Old_Flow';
        spec.actions.add(action('read_only_ok', 'Flow', 'Review_Flow', 'Row'));
        RelatedListTestData.register(spec);
        System.runAs(reader) {
            RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(spec.definitionKey, acct.Id, 5));
            Assert.areEqual(RelatedListController.STATUS_OK, res.status, 'message: ' + res.message);
            Assert.areEqual(1, res.context.actions.size(), 'v1 rule: legacy Flow only for users who can edit');
            Assert.areEqual('read_only_ok', res.context.actions[0].key);
        }
    }

    @IsTest
    static void newIsAnOrderedActionWithShowAs() {
        Account acct = RelatedListTestData.accountWithContacts('NewFirst', 1);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        RelatedListDefinitions.ActionSpec newAction = action('n', 'Standard', 'New', 'List');
        newAction.display = 'Button';
        newAction.label = 'Add contact';
        RelatedListDefinitions.ActionSpec flowInMenu = action('f', 'Flow', 'Some_Flow', 'List');
        flowInMenu.display = 'Menu';
        spec.actions.add(newAction);
        spec.actions.add(flowInMenu);
        RelatedListController.ListContext ctx = contextFor(spec, acct.Id);
        Assert.areEqual(2, ctx.actions.size(), 'no extra New is appended when a New row exists');
        Assert.areEqual('standard', ctx.actions[0].type);
        Assert.areEqual('Add contact', ctx.actions[0].label);
        Assert.areEqual('button', ctx.actions[0].display);
        Assert.areEqual('menu', ctx.actions[1].display);

        RelatedListDefinitions.ListSpec hidden = RelatedListTestData.accountContacts();
        hidden.definitionKey = 'No_New';
        hidden.allowCreate = false;
        RelatedListController.ListContext ctx2 = contextFor(hidden, acct.Id);
        Assert.areEqual(0, ctx2.actions.size(), 'New hidden when the list does not allow it');
    }

    @IsTest
    static void newIsHiddenFromUsersWhoCannotCreate() {
        Account acct = RelatedListTestData.accountWithContacts('NoCreate', 1);
        User reader = RelatedListTestData.restrictedUser(
            'arlnew',
            new List<RelatedListTestData.ObjectAccess>{ new RelatedListTestData.ObjectAccess('Account'), new RelatedListTestData.ObjectAccess('Contact') },
            new List<String>{ 'Contact.AccountId' },
            false
        );
        RelatedListTestData.giveToUser(acct, reader);
        RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
        spec.actions.add(action('n', 'Standard', 'New', 'List'));
        RelatedListTestData.register(spec);
        System.runAs(reader) {
            RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(spec.definitionKey, acct.Id, 5));
            Assert.areEqual(0, res.context.actions.size(), 'read-only users never see New');
        }
    }

    @IsTest
    static void invalidActionsAreConfigurationErrors() {
        Account acct = RelatedListTestData.accountWithContacts('Invalid', 1);
        List<RelatedListDefinitions.ActionSpec> bad = new List<RelatedListDefinitions.ActionSpec>{
            action('t', 'Script', 'X', 'List'),
            action('p', 'Flow', 'X', 'Sidebar'),
            action('f', 'Flow', 'Bad Flow!', 'List'),
            action('q', 'Quick_Action', 'a.b.c', 'Row'),
            action('s', 'Standard', 'Delete', 'List'),
            action('sr', 'Standard', 'New', 'Row')
        };
        Integer i = 0;
        for (RelatedListDefinitions.ActionSpec a : bad) {
            RelatedListDefinitions.ListSpec spec = RelatedListTestData.accountContacts();
            spec.definitionKey = 'Bad_Action_' + i++;
            spec.actions.add(a);
            RelatedListTestData.register(spec);
            RelatedListController.ListResponse res = RelatedListController.getRows(RelatedListTestData.request(spec.definitionKey, acct.Id, 5));
            Assert.areEqual(RelatedListController.STATUS_CONFIG, res.status, a.key + ' => ' + res.message);
        }
        RelatedListDefinitions.ListSpec badDisplay = RelatedListTestData.accountContacts();
        badDisplay.definitionKey = 'Bad_Display';
        RelatedListDefinitions.ActionSpec d = action('d', 'Flow', 'X', 'List');
        d.display = 'Sidebar';
        badDisplay.actions.add(d);
        RelatedListTestData.register(badDisplay);
        Assert.areEqual(RelatedListController.STATUS_CONFIG, RelatedListController.getRows(RelatedListTestData.request('Bad_Display', acct.Id, 5)).status);

        RelatedListDefinitions.ListSpec tooMany = RelatedListTestData.accountContacts();
        tooMany.definitionKey = 'Too_Many';
        for (Integer n = 0; n < 11; n++) {
            tooMany.actions.add(action('f' + n, 'Flow', 'Flow_' + n, 'List'));
        }
        RelatedListTestData.register(tooMany);
        Assert.areEqual(RelatedListController.STATUS_CONFIG, RelatedListController.getRows(RelatedListTestData.request('Too_Many', acct.Id, 5)).status);
    }

    // ===== BUILDER =====

    private static RelatedListBuilderController.ActionDraft draftAction(String type, String target, String placement) {
        RelatedListBuilderController.ActionDraft a = new RelatedListBuilderController.ActionDraft();
        a.actionType = type;
        a.target = target;
        a.placement = placement;
        return a;
    }

    private static RelatedListBuilderController.DefinitionDraft draftWithActions() {
        RelatedListBuilderController.DefinitionDraft d = new RelatedListBuilderController.DefinitionDraft();
        d.isNew = true;
        d.label = 'Contacts With Actions';
        d.active = true;
        d.parentObject = 'Account';
        d.childObject = 'Contact';
        d.lookupField = 'AccountId';
        RelatedListBuilderController.ColumnDraft c = new RelatedListBuilderController.ColumnDraft();
        c.fieldPath = 'Name';
        c.visible = true;
        d.columns = new List<RelatedListBuilderController.ColumnDraft>{ c };
        d.actions = new List<RelatedListBuilderController.ActionDraft>{
            draftAction('Flow', 'First_Flow', 'List'),
            draftAction('Flow', 'Second_Flow', 'List'),
            draftAction('Quick_Action', 'NewTask', 'List'),
            draftAction('Quick_Action', 'LogACall', 'Row')
        };
        return d;
    }

    @IsTest
    static void builderListsOnlyLaunchableQuickActions() {
        RelatedListBuilderService.adminPermissionOverride = true;
        Set<String> names = new Set<String>();
        for (RelatedListBuilderController.Option o : RelatedListBuilderController.listQuickActions('Contact')) {
            names.add(o.value);
            Assert.areNotEqual('Post', o.description, 'feed publisher actions are excluded');
        }
        Assert.isTrue(names.contains('LogACall') || names.contains('NewTask'), String.valueOf(names));
        for (String n : names) {
            Assert.isFalse(n.startsWith('FeedItem.'), n);
        }
    }

    @IsTest
    static void builderValidatesEachAction() {
        RelatedListBuilderService.adminPermissionOverride = true;
        RelatedListBuilderController.DefinitionDraft d = draftWithActions();
        Assert.isTrue(RelatedListBuilderController.validateDraft(d).valid, String.valueOf(RelatedListBuilderController.validateDraft(d).issues));

        d.actions.add(draftAction('Quick_Action', 'Contact.Does_Not_Exist', 'Row')); // index 4
        d.actions.add(draftAction('Flow', 'First_Flow', 'List')); // index 5: duplicate
        d.actions.add(draftAction('Flow', '', 'List')); // index 6: no target
        RelatedListBuilderController.ValidationResult vr = RelatedListBuilderController.validateDraft(d);
        Assert.isFalse(vr.valid);
        Set<Integer> errorRows = new Set<Integer>();
        Boolean flowWarning = false;
        for (RelatedListBuilderController.Issue i : vr.issues) {
            if (i.severity == 'error' && i.actionIndex != null) {
                errorRows.add(i.actionIndex);
            }
            flowWarning = flowWarning || (i.severity == 'warning' && i.actionIndex == 0 && i.message.contains('no active screen flow'));
        }
        Assert.areEqual(new Set<Integer>{ 4, 5, 6 }, errorRows, String.valueOf(vr.issues));
        Assert.isTrue(flowWarning, 'missing flows warn but do not block');
    }

    @IsTest
    static void builderSavesActionRecordsInOrder() {
        RelatedListBuilderService.adminPermissionOverride = true;
        CapturingDeployer deployer = new CapturingDeployer();
        RelatedListBuilderService.deployer = deployer;
        RelatedListBuilderController.SaveResult res = RelatedListBuilderController.saveDraft(draftWithActions());
        Assert.areEqual('QUEUED', res.status, String.valueOf(res.issues));
        List<Map<String, Object>> actions = new List<Map<String, Object>>();
        for (Metadata.Metadata m : deployer.captured.getMetadata()) {
            Metadata.CustomMetadata md = (Metadata.CustomMetadata) m;
            Map<String, Object> values = new Map<String, Object>{ 'fullName' => md.fullName };
            for (Metadata.CustomMetadataValue v : md.values) {
                values.put(v.field, v.value);
            }
            if (md.fullName.startsWith('Advanced_Related_List.')) {
                Assert.isNull(values.get('Flow_API_Name__c'), 'the single legacy Flow field is no longer written');
            }
            if (md.fullName.startsWith('Advanced_Related_List_Action.')) {
                actions.add(values);
            }
        }
        Assert.areEqual(4, actions.size());
        Map<Decimal, Map<String, Object>> byOrder = new Map<Decimal, Map<String, Object>>();
        for (Map<String, Object> a : actions) {
            byOrder.put((Decimal) a.get('Order__c'), a);
            Assert.areEqual('Contacts_With_Actions', a.get('Definition__c'));
            Assert.areEqual(false, a.get('Removed__c'));
            Assert.isFalse(((String) a.get('fullName')).substringAfter('.').contains('__'));
        }
        Assert.areEqual('First_Flow', byOrder.get(10).get('Target__c'));
        Assert.areEqual('Second_Flow', byOrder.get(20).get('Target__c'));
        Assert.areEqual('Quick_Action', byOrder.get(30).get('Action_Type__c'));
        Assert.areEqual('Row', byOrder.get(40).get('Placement__c'));
    }

    @IsTest
    static void builderShowsNewAsAnActionRowAndSavesTheChoice() {
        RelatedListBuilderService.adminPermissionOverride = true;
        RelatedListBuilderController.DefinitionDraft loaded = RelatedListBuilderController.getDefinition('Account_Contacts');
        RelatedListBuilderController.ActionDraft last = loaded.actions[loaded.actions.size() - 1];
        Assert.areEqual('Standard', last.actionType, 'lists from before get New as the last header action');
        Assert.areEqual('New', last.target);
        Assert.areEqual('Button', last.display);

        CapturingDeployer deployer = new CapturingDeployer();
        RelatedListBuilderService.deployer = deployer;
        RelatedListBuilderController.DefinitionDraft d = draftWithActions();
        RelatedListBuilderController.ActionDraft newFirst = draftAction('Standard', 'New', 'List');
        newFirst.display = 'Menu';
        d.actions.add(0, newFirst);
        d.actions[1].display = 'Button';
        d.allowCreate = false; // derived from the New row, not this flag
        RelatedListBuilderController.SaveResult res = RelatedListBuilderController.saveDraft(d);
        Assert.areEqual('QUEUED', res.status, String.valueOf(res.issues));
        Boolean allowCreate;
        Map<Decimal, Map<String, Object>> byOrder = new Map<Decimal, Map<String, Object>>();
        for (Metadata.Metadata m : deployer.captured.getMetadata()) {
            Metadata.CustomMetadata md = (Metadata.CustomMetadata) m;
            Map<String, Object> values = new Map<String, Object>();
            for (Metadata.CustomMetadataValue v : md.values) {
                values.put(v.field, v.value);
            }
            if (md.fullName.startsWith('Advanced_Related_List.')) {
                allowCreate = (Boolean) values.get('Allow_Create__c');
            } else if (md.fullName.startsWith('Advanced_Related_List_Action.')) {
                byOrder.put((Decimal) values.get('Order__c'), values);
            }
        }
        Assert.isTrue(allowCreate, 'Allow Create mirrors the New row');
        Assert.areEqual('Standard', byOrder.get(10).get('Action_Type__c'));
        Assert.areEqual('Menu', byOrder.get(10).get('Display__c'));
        Assert.areEqual('Button', byOrder.get(20).get('Display__c'));
        Assert.isNull(byOrder.get(50).get('Display__c'), 'row actions have no Show as');

        RelatedListBuilderController.DefinitionDraft noNew = draftWithActions();
        noNew.allowCreate = false;
        RelatedListBuilderService.normalize(noNew);
        Assert.isFalse(noNew.allowCreate, 'no New row means no New button');

        RelatedListBuilderController.DefinitionDraft badStandard = draftWithActions();
        badStandard.actions.add(draftAction('Standard', 'Delete', 'List'));
        badStandard.actions.add(draftAction('Standard', 'New', 'Row'));
        RelatedListBuilderController.ValidationResult vr = RelatedListBuilderController.validateDraft(badStandard);
        Assert.isFalse(vr.valid, String.valueOf(vr.issues));
    }

    @IsTest
    static void legacyFlowInADraftIsMigratedIntoAnAction() {
        RelatedListBuilderController.DefinitionDraft d = draftWithActions();
        d.actions.clear();
        d.flowApiName = 'Old_Flow';
        RelatedListBuilderService.normalize(d);
        Assert.isNull(d.flowApiName);
        Assert.areEqual(1, d.actions.size());
        Assert.areEqual('Old_Flow', d.actions[0].target);
        Assert.areEqual('List', d.actions[0].placement);
        String sig = RelatedListBuilderService.signatureOf(d);
        d.actions[0].placement = 'Row';
        Assert.areNotEqual(sig, RelatedListBuilderService.signatureOf(d), 'actions are part of the saved signature');
    }
}
