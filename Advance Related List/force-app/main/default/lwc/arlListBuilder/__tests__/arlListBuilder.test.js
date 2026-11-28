import { createElement } from 'lwc';
import ArlListBuilder, { toDeveloperName } from 'c/arlListBuilder';
import getAccess from '@salesforce/apex/RelatedListBuilderController.getAccess';
import listDefinitions from '@salesforce/apex/RelatedListBuilderController.listDefinitions';
import getDefinition from '@salesforce/apex/RelatedListBuilderController.getDefinition';
import listObjects from '@salesforce/apex/RelatedListBuilderController.listObjects';
import listRelationships from '@salesforce/apex/RelatedListBuilderController.listRelationships';
import listFields from '@salesforce/apex/RelatedListBuilderController.listFields';
import listFlows from '@salesforce/apex/RelatedListBuilderController.listFlows';
import listQuickActions from '@salesforce/apex/RelatedListBuilderController.listQuickActions';
import validateDraft from '@salesforce/apex/RelatedListBuilderController.validateDraft';
import saveDraft from '@salesforce/apex/RelatedListBuilderController.saveDraft';
import getSignature from '@salesforce/apex/RelatedListBuilderController.getSignature';
import LightningConfirm from 'lightning/confirm';

jest.mock('@salesforce/apex/RelatedListBuilderController.getAccess', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.listDefinitions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.getDefinition', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.listObjects', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.listRelationships', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.listFields', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.listFlows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.listQuickActions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.validateDraft', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.saveDraft', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListBuilderController.getSignature', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('lightning/confirm', () => ({ __esModule: true, default: { open: jest.fn() } }));

const DEFINITIONS = [
    { developerName: 'Account_Contacts', label: 'Account Contacts', parentObject: 'Account', childObject: 'Contact', lookupField: 'AccountId', active: true, columnCount: 2 },
    { developerName: 'Old_List', label: 'Old List', parentObject: 'Account', childObject: 'Case', lookupField: 'AccountId', active: false, columnCount: 1 }
];
const RELATIONSHIPS = [
    { value: 'Contact.AccountId', label: 'Contacts (via Account ID)', childObject: 'Contact', childLabel: 'Contacts', lookupField: 'AccountId', lookupLabel: 'Account ID' },
    { value: 'Opportunity.AccountId', label: 'Opportunities (via Account ID)', childObject: 'Opportunity', childLabel: 'Opportunities', lookupField: 'AccountId', lookupLabel: 'Account ID' }
];
const CONTACT_FIELDS = [
    { apiName: 'Name', label: 'Full Name', canSearch: true, canFilter: true, canSort: true, canEdit: false },
    { apiName: 'MailingAddress', label: 'Mailing Address', canSearch: false, canFilter: false, canSort: false, canEdit: true },
    { apiName: 'AccountId', label: 'Account ID', canSearch: false, canFilter: false, canSort: false, canEdit: true, relationshipName: 'Account', targetObject: 'Account', targetLabel: 'Account' }
];
const ACCOUNT_FIELDS = [{ apiName: 'Name', label: 'Account Name', canSearch: true, canFilter: true, canSort: true, canEdit: true }];
const CONTACTS_DEF = {
    developerName: 'Account_Contacts',
    label: 'Account Contacts',
    active: true,
    parentObject: 'Account',
    childObject: 'Contact',
    lookupField: 'AccountId',
    defaultSortField: 'Name',
    defaultSortDirection: 'ASC',
    allowCreate: true,
    allowEdit: true,
    allowDelete: true,
    allowBulkDelete: false,
    flowApiName: null,
    signature: 'sig-1',
    actions: [{ developerName: 'AC_Action_1', actionType: 'Flow', target: 'Update_Contacts', label: 'Update', placement: 'List' }],
    columns: [
        { developerName: 'AC_Name', fieldPath: 'Name', label: null, visible: true, searchable: true, filterable: false, sortable: true, editable: false },
        { developerName: 'AC_Address', fieldPath: 'MailingAddress', label: 'Address', visible: true, searchable: false, filterable: false, sortable: false, editable: false },
        { developerName: 'AC_Acct', fieldPath: 'Account.Name', label: null, visible: true, searchable: false, filterable: false, sortable: false, editable: false }
    ]
};

function flush() {
    return Array.from({ length: 15 }).reduce((p) => p.then(() => undefined), Promise.resolve());
}

async function mount() {
    const el = createElement('c-arl-list-builder', { is: ArlListBuilder });
    document.body.appendChild(el);
    await flush();
    return el;
}

const $ = (el, s) => el.shadowRoot.querySelector(s);
const $$ = (el, s) => [...el.shadowRoot.querySelectorAll(s)];

function change(target, detailValue, extra = {}) {
    Object.assign(target, extra);
    target.dispatchEvent(new CustomEvent('change', { detail: { value: detailValue } }));
}

async function openContacts(el) {
    $$(el, '[data-id="definitions"] a')[0].click();
    await flush();
}

describe('c-arl-list-builder', () => {
    beforeEach(() => {
        getAccess.mockResolvedValue({ canManage: true });
        listDefinitions.mockResolvedValue(DEFINITIONS);
        listObjects.mockResolvedValue([
            { label: 'Account', value: 'Account' },
            { label: 'Opportunity', value: 'Opportunity' }
        ]);
        listFlows.mockResolvedValue([{ label: 'Update Contacts', value: 'Update_Contacts' }]);
        listQuickActions.mockImplementation(({ objectApiName }) =>
            Promise.resolve(objectApiName === 'Contact' ? [{ label: 'Log a Call', value: 'LogACall', description: 'LogACall' }] : [{ label: 'New Task', value: 'NewTask', description: 'Create' }])
        );
        listRelationships.mockResolvedValue(RELATIONSHIPS);
        listFields.mockImplementation(({ objectApiName }) => Promise.resolve(objectApiName === 'Account' ? ACCOUNT_FIELDS : CONTACT_FIELDS));
        getDefinition.mockResolvedValue(JSON.parse(JSON.stringify(CONTACTS_DEF)));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    it('explains why a user without access cannot use the builder', async () => {
        getAccess.mockResolvedValue({ canManage: false, reason: 'You need the "Tekenable Advance Related List Admin" permission set.' });
        const el = await mount();
        expect($(el, '[data-id="no-access"]').textContent).toContain('Tekenable Advance Related List Admin');
        expect(listDefinitions).not.toHaveBeenCalled();
        expect($(el, '[data-id="new"]').disabled).toBe(true);
    });

    it('lists definitions with inactive badges and filters them', async () => {
        const el = await mount();
        const items = $$(el, '[data-id="definitions"] li');
        expect(items).toHaveLength(2);
        expect(items[0].textContent).toContain('Contact via AccountId · 2 columns');
        expect(items[1].textContent).toContain('Inactive');
        const search = $(el, '[data-id="list-search"]');
        search.value = 'old';
        search.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect($$(el, '[data-id="definitions"] li')).toHaveLength(1);
    });

    it('opens a definition with its relationship, columns and capability limits', async () => {
        const el = await mount();
        await openContacts(el);
        expect(getDefinition).toHaveBeenCalledWith({ developerName: 'Account_Contacts' });
        expect(listRelationships).toHaveBeenCalledWith({ parentObject: 'Account' });
        expect($(el, '[data-id="editor-heading"]').textContent).toBe('Account Contacts');
        expect($(el, '[data-id="api-name"]').disabled).toBe(true);
        expect($(el, '[data-id="relationship"]').value).toBe('Contact.AccountId');
        expect($(el, '[data-id="relationship-help"]').textContent).toContain('Shows Contacts whose "Account ID" is this record');

        const rows = $$(el, '[data-id="columns"] tbody tr');
        expect(rows).toHaveLength(3);
        expect(rows[0].textContent).toContain('Full Name');
        expect(rows[2].textContent).toContain('Account: Account Name'); // resolved through the relationship
        const addressSort = rows[1].querySelector('[data-flag="sortable"]');
        expect(addressSort.disabled).toBe(true);
        expect(rows[1].querySelector('td[title]').getAttribute('title')).toBe("This field type can't be searched.");
        expect(rows[2].querySelector('[data-flag="editable"]').disabled).toBe(true); // related field
        expect(rows[0].querySelector('[data-flag="sortable"]').disabled).toBe(false);
        expect($(el, '[data-id="save"]').disabled).toBe(true); // nothing changed yet
        const savedAction = $(el, '[data-id="actions"] tbody tr');
        expect(savedAction.querySelector('[data-role="action-target"]').value).toBe('Update_Contacts');
        expect(savedAction.querySelector('[data-role="action-label"]').value).toBe('Update');
    });

    it('creates a list: suggested API name, relationship, columns via the picker, reorder, remove', async () => {
        const el = await mount();
        $(el, '[data-id="new"]').click();
        await flush();
        change($(el, '[data-id="label"]'), undefined, { value: 'Account Opportunities 2' });
        await flush();
        expect($(el, '[data-id="api-name"]').value).toBe('Account_Opportunities_2');

        change($(el, '[data-id="parent"]'), 'Account');
        await flush();
        expect(listRelationships).toHaveBeenCalledWith({ parentObject: 'Account' });
        expect($(el, '[data-id="add-column"]').disabled).toBe(true); // no relationship yet
        change($(el, '[data-id="relationship"]'), 'Contact.AccountId');
        await flush();
        expect($(el, '[data-id="add-column"]').disabled).toBe(false);

        $(el, '[data-id="add-column"]').click();
        await flush();
        const picker = $(el, 'c-arl-field-picker');
        expect(picker.rootObject).toBe('Contact');
        picker.dispatchEvent(new CustomEvent('select', { detail: { path: 'Name', labelHint: 'Full Name', meta: { canSearch: true, canFilter: true, canSort: true, canEdit: false } } }));
        await flush();
        $(el, '[data-id="add-column"]').click();
        await flush();
        $(el, 'c-arl-field-picker').dispatchEvent(new CustomEvent('select', { detail: { path: 'Account.Name', labelHint: 'Account: Account Name', meta: { canSearch: true, canFilter: true, canSort: true, canEdit: false } } }));
        await flush();

        let rows = $$(el, '[data-id="columns"] tbody tr');
        expect(rows).toHaveLength(2);
        change(rows[0].querySelector('[data-flag="searchable"]'), undefined, { checked: true });
        change(rows[1].querySelector('[data-flag="sortable"]'), undefined, { checked: true });
        change(rows[1].querySelector('[data-role="column-label"]'), undefined, { value: 'Company' });
        await flush();
        rows[1].querySelector('[data-direction="up"]').click();
        await flush();
        rows = $$(el, '[data-id="columns"] tbody tr');
        expect(rows[0].textContent).toContain('Account.Name');

        change($(el, '[data-id="sort-field"]'), 'Account.Name');
        await flush();
        expect($(el, '[data-id="sort-field"]').options.map((o) => o.value)).toEqual(['', 'Account.Name', 'Name']);

        // two actions: a header flow and a row quick action on the child object
        $(el, '[data-id="add-action"]').click();
        await flush();
        $(el, '[data-id="add-action"]').click();
        await flush();
        let actionRows = $$(el, '[data-id="actions"] tbody tr').slice(1); // row 1 is the default New button
        expect(actionRows).toHaveLength(2);
        expect(actionRows[0].querySelector('[data-role="action-target"]').options).toEqual([{ label: 'Update Contacts (Update_Contacts)', value: 'Update_Contacts' }]);
        change(actionRows[0].querySelector('[data-role="action-target"]'), 'Update_Contacts');
        change(actionRows[0].querySelector('[data-role="action-label"]'), undefined, { value: 'Update' });
        change(actionRows[1].querySelector('[data-role="action-type"]'), 'Quick_Action');
        await flush();
        change($$(el, '[data-id="actions"] tbody tr')[2].querySelector('[data-role="action-placement"]'), 'Row');
        await flush();
        expect(listQuickActions).toHaveBeenLastCalledWith({ objectApiName: 'Contact' }); // row items run on the child
        actionRows = $$(el, '[data-id="actions"] tbody tr').slice(1);
        expect(actionRows[1].querySelector('[data-role="action-display"]').disabled).toBe(true); // Show as applies to header actions only
        expect(actionRows[1].querySelector('[data-role="action-display"]').options[0].label).toBe("In each row's menu");
        expect(actionRows[1].querySelector('[data-role="action-target"]').options.map((o) => o.value)).toEqual(['LogACall']);
        change(actionRows[1].querySelector('[data-role="action-target"]'), 'LogACall');
        await flush();

        saveDraft.mockResolvedValue({ status: 'QUEUED', developerName: 'Account_Opportunities_2', signature: 'new-sig', issues: [] });
        jest.useFakeTimers();
        $(el, '[data-id="save"]').click();
        await flush();
        const sent = saveDraft.mock.calls[0][0].draft;
        expect(sent).toEqual(
            expect.objectContaining({
                isNew: true,
                label: 'Account Opportunities 2',
                developerName: 'Account_Opportunities_2',
                parentObject: 'Account',
                childObject: 'Contact',
                lookupField: 'AccountId',
                defaultSortField: 'Account.Name',
                flowApiName: null
            })
        );
        expect(sent.allowCreate).toBe(true);
        expect(sent.actions).toEqual([
            { developerName: null, actionType: 'Standard', target: 'New', label: null, placement: 'List', display: 'Button' },
            { developerName: null, actionType: 'Flow', target: 'Update_Contacts', label: 'Update', placement: 'List', display: 'Button' },
            { developerName: null, actionType: 'Quick_Action', target: 'LogACall', label: null, placement: 'Row', display: null }
        ]);
        expect(sent.columns).toEqual([
            { developerName: null, fieldPath: 'Account.Name', label: 'Company', visible: true, searchable: false, filterable: false, sortable: true, editable: false },
            { developerName: null, fieldPath: 'Name', label: null, visible: true, searchable: true, filterable: false, sortable: false, editable: false }
        ]);
        expect($(el, '[data-id="status"]').textContent).toContain('Deploying');

        // first poll: not yet deployed; second poll: deployed
        getSignature.mockResolvedValueOnce(null).mockResolvedValueOnce('new-sig');
        getDefinition.mockResolvedValue({ ...JSON.parse(JSON.stringify(CONTACTS_DEF)), developerName: 'Account_Opportunities_2', label: 'Account Opportunities 2' });
        jest.advanceTimersByTime(2000);
        await flush();
        jest.advanceTimersByTime(2000);
        await flush();
        await flush();
        expect(getSignature).toHaveBeenCalledWith({ developerName: 'Account_Opportunities_2' });
        expect($(el, '[data-id="status"]').textContent).toBe('Saved.');
        expect($(el, '[data-id="placement-hint"]').textContent).toContain('Account_Opportunities_2');
    });

    it('reorders and removes actions and shows action problems next to the action', async () => {
        validateDraft.mockResolvedValue({
            valid: false,
            issues: [{ severity: 'error', message: 'Action 2: quick action "X" is not available for Contact.', columnIndex: null, actionIndex: 1 }]
        });
        const el = await mount();
        await openContacts(el);
        $(el, '[data-id="add-action"]').click();
        await flush();
        let rows = $$(el, '[data-id="actions"] tbody tr');
        expect(rows).toHaveLength(2);
        $(el, '[data-id="validate"]').click();
        await flush();
        rows = $$(el, '[data-id="actions"] tbody tr');
        expect(rows[1].textContent).toContain('is not available for Contact');
        expect($(el, '[data-id="issues"] .slds-theme_error')).toBeNull(); // shown on the row, not twice
        rows[1].querySelector('[data-role="action-move"][data-direction="up"]').click();
        await flush();
        rows = $$(el, '[data-id="actions"] tbody tr');
        expect(rows[1].querySelector('[data-role="action-target"]').value).toBe('Update_Contacts');
        rows[0].querySelector('[data-role="action-remove"]').click();
        await flush();
        expect($$(el, '[data-id="actions"] tbody tr')).toHaveLength(1);
    });

    it('treats New as an ordered action that can be moved, shown in More, or removed', async () => {
        const el = await mount();
        $(el, '[data-id="new"]').click();
        await flush();
        let rows = $$(el, '[data-id="actions"] tbody tr');
        expect(rows).toHaveLength(1);
        const newRow = rows[0];
        expect(newRow.querySelector('[data-role="action-type"]').value).toBe('Standard');
        expect(newRow.querySelector('[data-role="action-target"]').disabled).toBe(true);
        expect(newRow.querySelector('[data-role="action-placement"]').disabled).toBe(true);
        expect(newRow.querySelector('[data-role="action-display"]').options.map((o) => o.value)).toEqual(['Button', 'Menu', '']);
        change(newRow.querySelector('[data-role="action-display"]'), 'Menu');
        await flush();

        $(el, '[data-id="add-action"]').click();
        await flush();
        rows = $$(el, '[data-id="actions"] tbody tr');
        rows[1].querySelector('[data-role="action-move"][data-direction="up"]').click();
        await flush();
        rows = $$(el, '[data-id="actions"] tbody tr');
        expect(rows[1].querySelector('[data-role="action-type"]').value).toBe('Standard');
        expect(rows[1].querySelector('[data-role="action-display"]').value).toBe('Menu');

        change(rows[0].querySelector('[data-role="action-type"]'), 'Standard');
        await flush();
        rows = $$(el, '[data-id="actions"] tbody tr');
        expect(rows[0].querySelector('[data-role="action-target"]').value).toBe('New');
        expect(rows[0].querySelector('[data-role="action-placement"]').value).toBe('List');

        rows.forEach((r) => r.querySelector('[data-role="action-remove"]').click());
        await flush();
        validateDraft.mockResolvedValue({ valid: true, issues: [] });
        $(el, '[data-id="validate"]').click();
        await flush();
        const sent = validateDraft.mock.calls[0][0].draft;
        expect(sent.allowCreate).toBe(false);
        expect(sent.actions).toEqual([]);
    });

    it('removes a column and clears it as the default sort', async () => {
        const el = await mount();
        await openContacts(el);
        $$(el, '[data-role="remove"]')[0].click();
        await flush();
        expect($$(el, '[data-id="columns"] tbody tr')).toHaveLength(2);
        expect($(el, '[data-id="sort-field"]').value).toBe('');
        expect($(el, '[data-id="save"]').disabled).toBe(false);
    });

    it('shows validation errors next to their columns and blocks nothing else', async () => {
        validateDraft.mockResolvedValue({
            valid: false,
            issues: [
                { severity: 'error', message: 'Column 2 (MailingAddress): this field type cannot be sorted.', columnIndex: 1 },
                { severity: 'error', message: 'Enter a label.', columnIndex: null },
                { severity: 'warning', message: 'Bulk delete also requires a permission set.', columnIndex: null }
            ]
        });
        const el = await mount();
        await openContacts(el);
        $(el, '[data-id="validate"]').click();
        await flush();
        expect(validateDraft).toHaveBeenCalled();
        const rows = $$(el, '[data-id="columns"] tbody tr');
        expect(rows[1].textContent).toContain('cannot be sorted');
        expect($(el, '[data-id="issues"] .slds-theme_error').textContent).toContain('Enter a label.');
        expect($(el, '[data-id="issues"] .slds-theme_warning').textContent).toContain('Bulk delete');
        expect($(el, '[data-id="status"]').textContent).toBe('2 problem(s) to fix before saving.');
    });

    it('keeps the draft when the server rejects the save', async () => {
        saveDraft.mockResolvedValue({ status: 'INVALID', issues: [{ severity: 'error', message: 'A list definition named "X" already exists.', columnIndex: null }] });
        const el = await mount();
        await openContacts(el);
        change($(el, '[data-id="active"]'), undefined, { checked: false });
        await flush();
        $(el, '[data-id="save"]').click();
        await flush();
        expect($(el, '[data-id="issues"]').textContent).toContain('already exists');
        expect(getSignature).not.toHaveBeenCalled();
    });

    it('reports a deployment that does not finish', async () => {
        saveDraft.mockResolvedValue({ status: 'QUEUED', developerName: 'Account_Contacts', signature: 'never', issues: [] });
        getSignature.mockResolvedValue('sig-1');
        const el = await mount();
        await openContacts(el);
        change($(el, '[data-id="label"]'), undefined, { value: 'Renamed' });
        await flush();
        jest.useFakeTimers();
        $(el, '[data-id="save"]').click();
        await flush();
        for (let i = 0; i < 46; i++) {
            jest.advanceTimersByTime(2000);
            // eslint-disable-next-line no-await-in-loop
            await flush();
        }
        expect($(el, '[data-id="status"]').textContent).toContain('Deployment Status');
    });

    it('asks before discarding unsaved changes', async () => {
        LightningConfirm.open.mockResolvedValue(false);
        const el = await mount();
        await openContacts(el);
        change($(el, '[data-id="label"]'), undefined, { value: 'Changed' });
        await flush();
        $(el, '[data-id="new"]').click();
        await flush();
        expect(LightningConfirm.open).toHaveBeenCalled();
        expect($(el, '[data-id="editor-heading"]').textContent).toBe('Changed');
    });

    it('suggests valid API names', () => {
        expect(toDeveloperName('Account Opportunities')).toBe('Account_Opportunities');
        expect(toDeveloperName('2024 Deals!')).toBe('L_2024_Deals');
        expect(toDeveloperName('x'.repeat(60))).toHaveLength(40);
    });
});
