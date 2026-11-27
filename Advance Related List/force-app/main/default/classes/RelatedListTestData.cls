/**
 * @description Test fixtures for the Advanced Related List. Builds least-privilege users from the
 *              "Minimum Access - Salesforce" profile plus a permission set with explicit object,
 *              field and custom permissions, so CRUD/FLS enforcement is exercised for real.
 */
@IsTest
public class RelatedListTestData {
    public static final String MIN_ACCESS_PROFILE = 'Minimum Access - Salesforce';

    /** @description Object permission flags for a test permission set. */
    public class ObjectAccess {
        public String objectName;
        public Boolean canRead = true;
        public Boolean canEdit = false;
        public Boolean canDelete = false;
        public Boolean canCreate = false;
        public ObjectAccess(String objectName) {
            this.objectName = objectName;
        }
        public ObjectAccess edit() {
            this.canEdit = true;
            return this;
        }
        public ObjectAccess remove() {
            this.canEdit = true;
            this.canDelete = true;
            return this;
        }
    }

    // ===== SPECS (Custom Metadata cannot be inserted in tests) =====

    /**
     * @description Registers an in-memory definition, exactly as the CMT loader would return it.
     * @param spec spec to register under spec.definitionKey
     */
    public static void register(RelatedListDefinitions.ListSpec spec) {
        if (RelatedListDefinitions.testDefinitions == null) {
            RelatedListDefinitions.testDefinitions = new Map<String, RelatedListDefinitions.ListSpec>();
        }
        RelatedListDefinitions.testDefinitions.put(spec.definitionKey, spec);
    }

    /**
     * @description Account -> Contacts definition mirroring the shipped example.
     * @return spec
     */
    public static RelatedListDefinitions.ListSpec accountContacts() {
        RelatedListDefinitions.ListSpec spec = definition('Test_Account_Contacts', 'Account', 'Contact', 'AccountId');
        spec.defaultSortField = 'Name';
        spec.defaultSortDirection = 'ASC';
        spec.allowBulkDelete = true;
        spec.columns.add(column('c_name', 'Name', true, true, false, true));
        spec.columns.add(column('c_title', 'Title', true, true, true, true));
        spec.columns.add(column('c_email', 'Email', true, true, true, true));
        spec.columns.add(column('c_phone', 'Phone', true, true, true, false));
        spec.columns.add(column('c_birth', 'Birthdate', true, false, true, true));
        spec.columns.add(column('c_addr', 'MailingAddress', true, false, false, false));
        spec.columns.add(column('c_acct', 'Account.Name', true, false, false, false));
        return spec;
    }

    /**
     * @description Empty definition skeleton.
     * @param key DeveloperName
     * @param parent parent object
     * @param child child object
     * @param lookup lookup field
     * @return spec
     */
    public static RelatedListDefinitions.ListSpec definition(String key, String parent, String child, String lookup) {
        RelatedListDefinitions.ListSpec spec = new RelatedListDefinitions.ListSpec();
        spec.mode = RelatedListDefinitions.MODE_DEFINITION;
        spec.definitionKey = key;
        spec.parentObject = parent;
        spec.childObject = child;
        spec.lookupField = lookup;
        spec.allowCreate = true;
        spec.allowEdit = true;
        spec.allowDelete = true;
        return spec;
    }

    /**
     * @description Column spec.
     * @param key stable key
     * @param path field path
     * @param visible visible
     * @param searchable searchable
     * @param filterable filterable
     * @param sortable sortable
     * @return column spec
     */
    public static RelatedListDefinitions.ColumnSpec column(String key, String path, Boolean visible, Boolean searchable, Boolean filterable, Boolean sortable) {
        RelatedListDefinitions.ColumnSpec cs = new RelatedListDefinitions.ColumnSpec(key, path);
        cs.visible = visible;
        cs.searchable = searchable;
        cs.filterable = filterable;
        cs.sortable = sortable;
        return cs;
    }

    // ===== REQUESTS =====

    /**
     * @description Read request for a definition.
     * @param key definition key
     * @param parentId parent id
     * @param pageSize page size
     * @return request
     */
    public static RelatedListController.ListRequest request(String key, Id parentId, Integer pageSize) {
        RelatedListController.ListRequest req = new RelatedListController.ListRequest();
        req.definitionKey = key;
        req.parentId = parentId;
        req.pageSize = pageSize;
        req.filters = new List<RelatedListController.FilterInput>();
        return req;
    }

    /**
     * @description Filter input.
     * @param columnKey column key
     * @param operator operator
     * @param value value
     * @return filter
     */
    public static RelatedListController.FilterInput filter(String columnKey, String operator, String value) {
        RelatedListController.FilterInput f = new RelatedListController.FilterInput();
        f.columnKey = columnKey;
        f.operator = operator;
        f.value = value;
        return f;
    }

    // ===== DATA =====

    /**
     * @description Inserts an account with contacts.
     * @param name account name
     * @param contactCount number of contacts
     * @return account
     */
    public static Account accountWithContacts(String name, Integer contactCount) {
        Account acct = new Account(Name = name, BillingCity = 'Springfield');
        insert acct;
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < contactCount; i++) {
            contacts.add(
                new Contact(
                    AccountId = acct.Id,
                    FirstName = 'Test',
                    LastName = name + ' Contact ' + String.valueOf(i).leftPad(4, '0'),
                    Email = 'c' + i + '@example.com',
                    Phone = '555-0' + String.valueOf(i).leftPad(3, '0'),
                    Title = Math.mod(i, 3) == 0 ? null : 'Same Title',
                    MailingStreet = i + ' Main St',
                    MailingCity = 'Springfield',
                    MailingPostalCode = '12345'
                )
            );
        }
        insert contacts;
        return acct;
    }

    // ===== USERS =====

    /**
     * @description Creates a Minimum Access user with a dedicated permission set.
     * @param alias unique alias (max 8)
     * @param objects object permissions
     * @param readFields fields readable by the user, as Object.Field
     * @param bulkDelete grant the bulk-delete custom permission
     * @return user
     */
    public static User restrictedUser(String alias, List<ObjectAccess> objects, List<String> readFields, Boolean bulkDelete) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :MIN_ACCESS_PROFILE LIMIT 1];
            Assert.isFalse(profiles.isEmpty(), 'Tests require the "' + MIN_ACCESS_PROFILE + '" profile.');
            u = new User(
                Alias = alias,
                Email = alias + '@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'ARL ' + alias,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = profiles[0].Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = alias + '.' + Datetime.now().getTime() + '@arl-test.invalid'
            );
            insert u;

            PermissionSet ps = new PermissionSet(Name = 'ARL_Test_' + alias, Label = 'ARL Test ' + alias);
            insert ps;
            List<ObjectPermissions> ops = new List<ObjectPermissions>();
            for (ObjectAccess oa : objects) {
                ops.add(
                    new ObjectPermissions(
                        ParentId = ps.Id,
                        SobjectType = oa.objectName,
                        PermissionsRead = oa.canRead,
                        PermissionsCreate = oa.canCreate,
                        PermissionsEdit = oa.canEdit,
                        PermissionsDelete = oa.canDelete
                    )
                );
            }
            insert ops;
            List<FieldPermissions> fps = new List<FieldPermissions>();
            for (String qualified : readFields) {
                fps.add(new FieldPermissions(ParentId = ps.Id, SobjectType = qualified.substringBefore('.'), Field = qualified, PermissionsRead = true, PermissionsEdit = false));
            }
            // Non-permissionable fields (always readable) are rejected by the platform; ignore those rows.
            Database.insert(fps, false);
            if (bulkDelete) {
                CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = :RelatedListService.BULK_DELETE_PERMISSION LIMIT 1];
                insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
            }
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    /**
     * @description Transfers ownership so the restricted user can see the rows under any OWD.
     * @param acct account
     * @param owner new owner
     */
    public static void giveToUser(Account acct, User owner) {
        acct.OwnerId = owner.Id;
        update acct;
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id];
        for (Contact c : contacts) {
            c.OwnerId = owner.Id;
        }
        update contacts;
    }
}
