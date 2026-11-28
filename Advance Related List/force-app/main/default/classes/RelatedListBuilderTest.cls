/**
 * @description Tests for the Tekenable Related List Builder (controller, service, App Builder picklist).
 *              Apex tests cannot run Metadata API deployments, so a stub deployer captures the
 *              container and the tests assert the exact records that would be deployed.
 */
@IsTest
private class RelatedListBuilderTest {
    private class CapturingDeployer implements RelatedListBuilderService.Deployer {
        public Metadata.DeployContainer captured;
        public Integer calls = 0;
        public Id deploy(Metadata.DeployContainer container) {
            captured = container;
            calls++;
            return Id.valueOf('0Af000000000001');
        }
    }

    private static CapturingDeployer stubDeployer() {
        CapturingDeployer d = new CapturingDeployer();
        RelatedListBuilderService.deployer = d;
        RelatedListBuilderService.adminPermissionOverride = true;
        return d;
    }

    private static RelatedListBuilderController.ColumnDraft col(String path, Boolean searchable, Boolean filterable, Boolean sortable) {
        RelatedListBuilderController.ColumnDraft c = new RelatedListBuilderController.ColumnDraft();
        c.fieldPath = path;
        c.visible = true;
        c.searchable = searchable;
        c.filterable = filterable;
        c.sortable = sortable;
        c.editable = false;
        return c;
    }

    private static RelatedListBuilderController.DefinitionDraft opportunitiesDraft() {
        RelatedListBuilderController.DefinitionDraft d = new RelatedListBuilderController.DefinitionDraft();
        d.isNew = true;
        d.label = 'Account Opportunities (Builder)';
        d.active = true;
        d.parentObject = 'Account';
        d.childObject = 'Opportunity';
        d.lookupField = 'AccountId';
        d.defaultSortField = 'CloseDate';
        d.defaultSortDirection = 'DESC';
        d.allowCreate = true;
        d.allowEdit = true;
        d.allowDelete = true;
        d.allowBulkDelete = false;
        d.columns = new List<RelatedListBuilderController.ColumnDraft>{
            col('Name', true, false, true),
            col('StageName', false, true, false),
            col('Amount', false, true, true),
            col('CloseDate', false, true, true),
            col('Account.Owner.Name', false, false, false)
        };
        return d;
    }

    private static Map<String, Object> valuesOf(Metadata.CustomMetadata md) {
        Map<String, Object> values = new Map<String, Object>();
        for (Metadata.CustomMetadataValue v : md.values) {
            values.put(v.field, v.value);
        }
        return values;
    }

    private static Map<String, Metadata.CustomMetadata> recordsByName(Metadata.DeployContainer container) {
        Map<String, Metadata.CustomMetadata> result = new Map<String, Metadata.CustomMetadata>();
        for (Metadata.Metadata m : container.getMetadata()) {
            Metadata.CustomMetadata md = (Metadata.CustomMetadata) m;
            result.put(md.fullName, md);
        }
        return result;
    }

    // ===== ACCESS =====

    @IsTest
    static void accessRequiresCustomPermission() {
        RelatedListBuilderService.adminPermissionOverride = false;
        RelatedListBuilderController.Access a = RelatedListBuilderController.getAccess();
        Assert.isFalse(a.canManage);
        Assert.isTrue(a.reason.contains('Tekenable Advance Related List Admin'), a.reason);
        try {
            RelatedListBuilderController.listDefinitions();
            Assert.fail('endpoints must refuse users without access');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Tekenable Advance Related List Admin'), e.getMessage());
        }
    }

    @IsTest
    static void accessRequiresCustomizeApplication() {
        User u = RelatedListTestData.restrictedUser('arlbld', new List<RelatedListTestData.ObjectAccess>(), new List<String>(), false);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = :RelatedListBuilderService.ADMIN_PERMISSION LIMIT 1];
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ARL_Test_arlbld' LIMIT 1];
            insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
        }
        System.runAs(u) {
            RelatedListBuilderController.Access a = RelatedListBuilderController.getAccess();
            Assert.isFalse(a.canManage, 'custom permission alone is not enough');
            Assert.isTrue(a.reason.contains('Customize Application'), a.reason);
        }
    }

    @IsTest
    static void adminWithPermissionCanManage() {
        RelatedListBuilderService.adminPermissionOverride = true;
        Assert.isTrue(RelatedListBuilderController.getAccess().canManage, 'running admin has Customize Application');
    }

    // ===== READ =====

    @IsTest
    static void listsAndLoadsTheShippedDefinition() {
        RelatedListBuilderService.adminPermissionOverride = true;
        RelatedListBuilderController.DefinitionSummary summary;
        for (RelatedListBuilderController.DefinitionSummary s : RelatedListBuilderController.listDefinitions()) {
            if (s.developerName == 'Account_Contacts') {
                summary = s;
            }
        }
        Assert.isNotNull(summary, 'shipped example is listed');
        Assert.areEqual(9, summary.columnCount);
        Assert.areEqual('Contact', summary.childObject);

        RelatedListBuilderController.DefinitionDraft d = RelatedListBuilderController.getDefinition('Account_Contacts');
        Assert.areEqual(9, d.columns.size());
        Assert.areEqual('Name', d.columns[0].fieldPath, 'columns come back in Order__c order');
        Assert.areEqual('MailingCity', d.columns[8].fieldPath);
        Assert.isNotNull(d.signature);
        Assert.areEqual(d.signature, RelatedListBuilderController.getSignature('Account_Contacts'));
        Assert.isNull(RelatedListBuilderController.getSignature('Does_Not_Exist'));
        try {
            RelatedListBuilderController.getDefinition('Does_Not_Exist');
            Assert.fail('unknown definition');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not found'), e.getMessage());
        }
    }

    @IsTest
    static void browsesObjectsRelationshipsAndFields() {
        RelatedListBuilderService.adminPermissionOverride = true;
        Set<String> objects = new Set<String>();
        for (RelatedListBuilderController.Option o : RelatedListBuilderController.listObjects()) {
            objects.add(o.value);
        }
        Assert.isTrue(objects.contains('Account') && objects.contains('Opportunity'), 'record-page objects are offered');
        Assert.isFalse(objects.contains('Advanced_Related_List__mdt'), 'custom metadata types are not offered');

        Map<String, RelatedListBuilderController.RelationshipOption> rels = new Map<String, RelatedListBuilderController.RelationshipOption>();
        for (RelatedListBuilderController.RelationshipOption r : RelatedListBuilderController.listRelationships('Account')) {
            rels.put(r.value, r);
        }
        Assert.isTrue(rels.containsKey('Opportunity.AccountId'), 'Account -> Opportunities via AccountId');
        Assert.isTrue(rels.containsKey('Contact.AccountId'));
        Assert.areEqual('Opportunity', rels.get('Opportunity.AccountId').childObject);
        Assert.isTrue(rels.get('Opportunity.AccountId').label.contains('via'), rels.get('Opportunity.AccountId').label);

        Map<String, RelatedListBuilderController.FieldOption> fields = new Map<String, RelatedListBuilderController.FieldOption>();
        for (RelatedListBuilderController.FieldOption f : RelatedListBuilderController.listFields('Opportunity')) {
            fields.put(f.apiName, f);
        }
        Assert.isTrue(fields.get('StageName').canFilter, 'picklists can be filtered');
        Assert.isFalse(fields.get('StageName').canSort, 'picklists cannot be keyset-sorted');
        Assert.isTrue(fields.get('Amount').canSort);
        Assert.isTrue(fields.get('Name').canSearch);
        Assert.isFalse(fields.get('Amount').canSearch);
        Assert.areEqual('Account', fields.get('AccountId').relationshipName, 'lookups can be drilled into');
        Assert.areEqual('Account', fields.get('AccountId').targetObject);

        try {
            RelatedListBuilderController.listFields('Not_An_Object__c');
            Assert.fail('unknown object');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Not_An_Object__c'), e.getMessage());
        }
        Assert.isNotNull(RelatedListBuilderController.listFlows());
    }

    // ===== VALIDATION =====

    @IsTest
    static void validDraftPasses() {
        RelatedListBuilderService.adminPermissionOverride = true;
        RelatedListBuilderController.ValidationResult vr = RelatedListBuilderController.validateDraft(opportunitiesDraft());
        Assert.isTrue(vr.valid, String.valueOf(vr.issues));
    }

    @IsTest
    static void validationReportsEachProblemAgainstItsColumn() {
        RelatedListBuilderService.adminPermissionOverride = true;
        RelatedListBuilderController.DefinitionDraft d = opportunitiesDraft();
        d.columns[1].sortable = true; // StageName: picklist cannot be sorted
        d.columns[4].editable = true; // related field cannot be edited
        d.columns.add(col('Amount', false, false, false)); // duplicate
        d.columns.add(col('Account.Nope__c', false, false, false)); // bad path
        d.defaultSortField = 'StageName';
        d.flowApiName = 'Not_A_Real_Flow';
        RelatedListBuilderController.ValidationResult vr = RelatedListBuilderController.validateDraft(d);
        Assert.isFalse(vr.valid);
        Set<Integer> errorColumns = new Set<Integer>();
        String all = '';
        for (RelatedListBuilderController.Issue i : vr.issues) {
            all += i.severity + ':' + i.message + '\n';
            if (i.severity == 'error' && i.columnIndex != null) {
                errorColumns.add(i.columnIndex);
            }
        }
        Assert.isTrue(errorColumns.containsAll(new Set<Integer>{ 1, 4, 5, 6 }), all);
        Assert.isTrue(all.contains('cannot be sorted'), all);
        Assert.isTrue(all.contains('repeats the field'), all);
        Assert.isTrue(all.contains('default sort field'), all);
        Assert.isTrue(all.contains('warning:Action 1: no active screen flow'), all + ' (the legacy flow is validated as an action)');
    }

    @IsTest
    static void validationCoversDetailsAndRelationship() {
        RelatedListBuilderService.adminPermissionOverride = true;
        RelatedListBuilderController.DefinitionDraft blank = new RelatedListBuilderController.DefinitionDraft();
        blank.isNew = true;
        RelatedListBuilderController.ValidationResult vr = RelatedListBuilderController.validateDraft(blank);
        String all = String.valueOf(vr.issues);
        Assert.isFalse(vr.valid);
        Assert.isTrue(all.contains('Enter a label'), all);
        Assert.isTrue(all.contains('record page object'), all);
        Assert.isTrue(all.contains('related records'), all);
        Assert.isTrue(all.contains('at least one column'), all);

        RelatedListBuilderController.DefinitionDraft dup = opportunitiesDraft();
        dup.developerName = 'Account_Contacts';
        Assert.isTrue(String.valueOf(RelatedListBuilderController.validateDraft(dup).issues).contains('already exists'));

        RelatedListBuilderController.DefinitionDraft badName = opportunitiesDraft();
        badName.developerName = 'Bad__Name_';
        Assert.isFalse(RelatedListBuilderController.validateDraft(badName).valid);

        RelatedListBuilderController.DefinitionDraft hidden = opportunitiesDraft();
        for (RelatedListBuilderController.ColumnDraft c : hidden.columns) {
            c.visible = false;
        }
        Assert.isTrue(String.valueOf(RelatedListBuilderController.validateDraft(hidden).issues).contains('at least one column visible'));

        RelatedListBuilderController.DefinitionDraft wrongLookup = opportunitiesDraft();
        wrongLookup.lookupField = 'CampaignId';
        Assert.isFalse(RelatedListBuilderController.validateDraft(wrongLookup).valid, 'runtime resolver rejects a lookup that does not point to the parent');
    }

    // ===== SAVE =====

    @IsTest
    static void saveDeploysDefinitionAndColumnsInOrder() {
        CapturingDeployer deployer = stubDeployer();
        RelatedListBuilderController.SaveResult res = RelatedListBuilderController.saveDraft(opportunitiesDraft());
        Assert.areEqual('QUEUED', res.status, String.valueOf(res.issues));
        Assert.areEqual('Account_Opportunities_Builder', res.developerName, 'API name derived from the label');
        Assert.areEqual(1, deployer.calls);

        Map<String, Metadata.CustomMetadata> records = recordsByName(deployer.captured);
        Assert.areEqual(7, records.size(), 'definition + 5 columns + the New action row (Allow Create)');
        Map<String, Object> def = valuesOf(records.get('Advanced_Related_List.Account_Opportunities_Builder'));
        Assert.areEqual('Opportunity', def.get('Child_Object__c'));
        Assert.areEqual('AccountId', def.get('Relationship_Field__c'));
        Assert.areEqual('DESC', def.get('Default_Sort_Direction__c'));
        Assert.areEqual(false, def.get('Allow_Bulk_Delete__c'));

        Integer seen = 0;
        for (Metadata.CustomMetadata md : records.values()) {
            if (md.fullName.startsWith('Advanced_Related_List_Column.')) {
                Map<String, Object> v = valuesOf(md);
                Assert.areEqual('Account_Opportunities_Builder', v.get('Definition__c'));
                Assert.areEqual(false, v.get('Removed__c'));
                Assert.isTrue(md.label.length() <= 40);
                Assert.isFalse(md.fullName.substringAfter('.').contains('__'), md.fullName);
                seen++;
            }
        }
        Assert.areEqual(5, seen);
        Assert.isTrue(records.containsKey('Advanced_Related_List_Column.Account_Opportunit_Account_Owner_Name'), String.valueOf(records.keySet()));
        Assert.isNotNull(res.signature);
    }

    @IsTest
    static void saveFlagsDroppedColumnsAsRemovedAndKeepsNames() {
        CapturingDeployer deployer = stubDeployer();
        RelatedListBuilderController.DefinitionDraft d = RelatedListBuilderController.getDefinition('Account_Contacts');
        RelatedListBuilderController.ColumnDraft dropped = d.columns.remove(1); // AC_Title
        RelatedListBuilderController.ColumnDraft first = d.columns.remove(0);
        d.columns.add(first); // move Name to the end
        d.columns.add(col('Department', true, true, true));

        RelatedListBuilderController.SaveResult res = RelatedListBuilderController.saveDraft(d);
        Assert.areEqual('QUEUED', res.status, String.valueOf(res.issues));
        Map<String, Metadata.CustomMetadata> records = recordsByName(deployer.captured);
        Map<String, Object> removed = valuesOf(records.get('Advanced_Related_List_Column.' + dropped.developerName));
        Assert.areEqual(true, removed.get('Removed__c'), 'Metadata API cannot delete: dropped columns are flagged');
        Assert.areEqual('Title', removed.get('Field_Path__c'), 'all values are re-sent so nothing else changes');
        Map<String, Object> moved = valuesOf(records.get('Advanced_Related_List_Column.AC_Name'));
        Assert.areEqual(Decimal.valueOf(80), moved.get('Order__c'), 'existing column keeps its name and gets its new position');
        Assert.isTrue(records.containsKey('Advanced_Related_List_Column.Account_Contacts_Department'), String.valueOf(records.keySet()));
    }

    @IsTest
    static void invalidDraftIsNotDeployed() {
        CapturingDeployer deployer = stubDeployer();
        RelatedListBuilderController.DefinitionDraft d = opportunitiesDraft();
        d.columns[1].sortable = true;
        RelatedListBuilderController.SaveResult res = RelatedListBuilderController.saveDraft(d);
        Assert.areEqual('INVALID', res.status);
        Assert.areEqual(0, deployer.calls);
    }

    @IsTest
    static void signatureMatchesWhatTheLoaderWillRead() {
        stubDeployer();
        RelatedListBuilderController.DefinitionDraft loaded = RelatedListBuilderController.getDefinition('Account_Contacts');
        String before = loaded.signature;
        RelatedListBuilderService.normalize(loaded);
        Assert.areEqual(before, RelatedListBuilderService.signatureOf(loaded), 'normalisation does not change an unchanged definition');
        loaded.columns[0].sortable = !loaded.columns[0].sortable;
        Assert.areNotEqual(before, RelatedListBuilderService.signatureOf(loaded), 'any change alters the signature');
    }

    @IsTest
    static void developerNamesAreValid() {
        Assert.areEqual('Account_Opportunities', RelatedListBuilderService.developerNameFrom('Account Opportunities'));
        Assert.areEqual('L_2024_Deals', RelatedListBuilderService.developerNameFrom('2024 Deals!'));
        Assert.areEqual('A_B', RelatedListBuilderService.developerNameFrom('  A -- B  '));
        Assert.areEqual(40, RelatedListBuilderService.developerNameFrom('x'.repeat(60)).length());
    }

    // ===== APP BUILDER PICKLIST =====

    @IsTest
    static void appBuilderPicklistOffersDefinitionsForThePageObject() {
        VisualEditor.DesignTimePageContext account = new VisualEditor.DesignTimePageContext();
        account.entityName = 'Account';
        account.pageType = 'RecordPage';
        RelatedListDefinitionPicklist picklist = new RelatedListDefinitionPicklist(account);
        Set<String> values = new Set<String>();
        for (VisualEditor.DataRow row : picklist.getValues().getDataRows()) {
            values.add((String) row.getValue());
        }
        Assert.isTrue(values.contains('Account_Contacts'));
        Assert.isNull(picklist.getDefaultValue());

        VisualEditor.DesignTimePageContext caseCtx = new VisualEditor.DesignTimePageContext();
        caseCtx.entityName = 'Case';
        caseCtx.pageType = 'RecordPage';
        Set<String> caseValues = new Set<String>();
        for (VisualEditor.DataRow row : new RelatedListDefinitionPicklist(caseCtx).getValues().getDataRows()) {
            caseValues.add((String) row.getValue());
        }
        Assert.isFalse(caseValues.contains('Account_Contacts'), 'definitions for other objects are not offered');
    }
}
