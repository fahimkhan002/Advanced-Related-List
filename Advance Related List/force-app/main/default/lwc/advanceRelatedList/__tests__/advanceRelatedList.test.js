import { createElement } from 'lwc';
import AdvanceRelatedList from 'c/advanceRelatedList';
import getRows from '@salesforce/apex/RelatedListController.getRows';
import deleteRows from '@salesforce/apex/RelatedListController.deleteRows';
import { deleteRecord } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import EditModal from 'c/arlEditModal';
import FlowModal from 'c/arlFlowModal';
import { getNavigateCalls, resetNavigateCalls } from 'lightning/navigation';

jest.mock('@salesforce/apex/RelatedListController.getRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListController.deleteRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('lightning/confirm', () => ({ __esModule: true, default: { open: jest.fn() } }));
jest.mock('c/arlEditModal', () => ({ __esModule: true, default: { open: jest.fn() } }));
jest.mock('c/arlFlowModal', () => ({ __esModule: true, default: { open: jest.fn() } }));
jest.mock('lightning/pageReferenceUtils', () => ({
    __esModule: true,
    encodeDefaultFieldValues: jest.fn((values) =>
        Object.entries(values)
            .map(([k, v]) => `${k}=${v}`)
            .join(',')
    )
}));

const PARENT_ID = '001000000000001AAA';

const COLUMNS = [
    { key: 'c_name', label: 'Name', type: 'name', visible: true, sortable: true, filterable: false, searchable: true },
    {
        key: 'c_email',
        label: 'Email',
        type: 'email',
        visible: true,
        sortable: true,
        filterable: true,
        searchable: true,
        filterType: 'text',
        operators: ['equals', 'contains', 'isBlank']
    },
    {
        key: 'c_active',
        label: 'Active',
        type: 'boolean',
        visible: true,
        sortable: false,
        filterable: true,
        filterType: 'boolean',
        operators: ['equals']
    },
    { key: 'c_acct', label: 'Account', type: 'link', visible: true, sortable: false },
    { key: 'c_amt', label: 'Amount', type: 'currency', visible: true, sortable: true },
    { key: 'c_pct', label: 'Probability', type: 'percent', visible: true, sortable: false, scale: 0 },
    { key: 'c_city', label: 'City', type: 'text', visible: false, searchable: true }
];

const CONTEXT = {
    mode: 'definition',
    definitionKey: 'Account_Contacts',
    objectApiName: 'Contact',
    objectLabel: 'Contact',
    objectLabelPlural: 'Contacts',
    lookupField: 'AccountId',
    canCreate: true,
    canEdit: true,
    canDelete: true,
    canBulkDelete: true,
    flowApiName: 'Contact_Flow',
    editFields: ['Email'],
    sortKey: 'c_name',
    sortDirection: 'asc',
    omittedColumnCount: 0,
    maxDeleteBatch: 100
};

const ROWS = [
    {
        id: '003000000000001AAA',
        c_name: 'Ann Lee',
        c_name__id: '003000000000001AAA',
        c_email: 'ann@example.com',
        c_active: false,
        c_acct: 'Acme',
        c_acct__id: PARENT_ID,
        c_amt: 0,
        c_amt__cur: 'EUR',
        c_pct: 25
    },
    { id: '003000000000002AAA', c_name: 'Bob Ray', c_name__id: '003000000000002AAA' }
];

function okResponse(overrides = {}) {
    const { context, ...rest } = overrides;
    return {
        status: 'OK',
        columns: COLUMNS,
        rows: ROWS,
        totalCount: 2,
        totalCountCapped: false,
        hasMore: false,
        nextCursor: null,
        ...rest,
        context: { ...CONTEXT, ...(context || {}) }
    };
}

function flush() {
    // Drain chained microtasks without timers (tests also use fake timers).
    return Array.from({ length: 12 }).reduce((p) => p.then(() => undefined), Promise.resolve());
}

async function mount(props = {}) {
    const element = createElement('c-advance-related-list', { is: AdvanceRelatedList });
    Object.assign(element, { recordId: PARENT_ID, listDefinition: 'Account_Contacts', recordsPerPage: 2 }, props);
    document.body.appendChild(element);
    await flush();
    return element;
}

const $ = (element, selector) => element.shadowRoot.querySelector(selector);
const lastRequest = () => getRows.mock.calls[getRows.mock.calls.length - 1][0].request;

function captureToasts(element) {
    const toasts = [];
    element.addEventListener('lightning__showtoast', (e) => toasts.push(e.detail));
    return toasts;
}

describe('c-advance-related-list', () => {
    beforeEach(() => {
        getRows.mockResolvedValue(okResponse());
        resetNavigateCalls();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
    });

    describe('rendering', () => {
        it('requests the definition and renders visible columns and rows', async () => {
            const element = await mount();

            const request = lastRequest();
            expect(request.definitionKey).toBe('Account_Contacts');
            expect(request.parentId).toBe(PARENT_ID);
            expect(request.legacy).toBeNull();
            expect(request.cursor).toBeNull();
            expect(request.pageSize).toBe(2);

            const table = $(element, 'lightning-datatable');
            expect(table).not.toBeNull();
            const labels = table.columns.map((c) => c.label);
            expect(labels).toEqual(['Name', 'Email', 'Active', 'Account', 'Amount', 'Probability', undefined]);
            expect(labels).not.toContain('City'); // hidden search-only column
            expect(table.data).toHaveLength(2);
            expect($(element, '[data-id="count"]').textContent).toBe('(2)');
            expect($(element, 'h2').textContent).toContain('Contacts');
        });

        it('builds record links, keeps false and zero, and converts percent', async () => {
            const element = await mount();
            const table = $(element, 'lightning-datatable');
            const [ann, bob] = table.data;
            expect(ann.c_name__url).toBe('/lightning/r/003000000000001AAA/view');
            expect(ann.c_acct__url).toBe(`/lightning/r/${PARENT_ID}/view`);
            expect(ann.c_active).toBe(false);
            expect(ann.c_amt).toBe(0);
            expect(ann.c_pct).toBeCloseTo(0.25);
            expect(bob.c_email).toBeUndefined(); // absent optional key stays absent
            const amount = table.columns.find((c) => c.label === 'Amount');
            expect(amount.type).toBe('currency');
            expect(amount.typeAttributes.currencyCode).toEqual({ fieldName: 'c_amt__cur' });
            const name = table.columns.find((c) => c.label === 'Name');
            expect(name.type).toBe('url');
            expect(name.typeAttributes.label).toEqual({ fieldName: 'c_name' });
        });

        it('sends legacy App Builder properties when no definition key is set', async () => {
            await mount({
                listDefinition: undefined,
                childObjectApiName: 'Contact',
                parentLookupField: 'AccountId',
                fieldsToDisplay: 'Name,Email',
                searchableFields: 'Name',
                sortableFields: 'Name',
                columnLabels: 'Full Name',
                flowName: 'Legacy_Flow'
            });
            const request = lastRequest();
            expect(request.definitionKey).toBeNull();
            expect(request.legacy).toEqual({
                childObjectApiName: 'Contact',
                parentLookupField: 'AccountId',
                fieldsToDisplay: 'Name,Email',
                searchableFields: 'Name',
                sortableFields: 'Name',
                columnLabels: 'Full Name',
                flowName: 'Legacy_Flow'
            });
        });

        it('shows a capped total and ignores unsafe icon colours', async () => {
            getRows.mockResolvedValue(okResponse({ totalCount: 2000, totalCountCapped: true, hasMore: true, nextCursor: 'c1' }));
            const element = await mount({ iconBackgroundColor: 'red; background-image:url(x)' });
            expect($(element, '[data-id="count"]').textContent).toBe('(2,000+)');
            expect($(element, 'lightning-icon').getAttribute('style') || '').not.toContain('url(');
            expect($(element, '[data-id="page"]').textContent).toBe('Page 1');
        });

        it('applies a valid hex icon colour', async () => {
            const element = await mount({ iconBackgroundColor: '#1589EE' });
            expect($(element, 'lightning-icon').getAttribute('style')).toContain('#1589EE');
        });
    });

    describe('states', () => {
        it('shows the empty state when there are no rows and no criteria', async () => {
            getRows.mockResolvedValue(okResponse({ rows: [], totalCount: 0 }));
            const element = await mount();
            expect($(element, '[data-id="empty"]').textContent).toBe('No contacts yet.');
            expect($(element, 'lightning-datatable')).toBeNull();
        });

        it('shows a configuration error with zero data', async () => {
            getRows.mockResolvedValue({ status: 'CONFIG_ERROR', message: 'List definition "X" was not found.' });
            const element = await mount();
            expect($(element, '[data-id="config-error"]').textContent).toContain('List definition "X" was not found.');
            expect($(element, 'lightning-datatable')).toBeNull();
            expect($(element, '[data-id="live"]').textContent).toContain('was not found');
        });

        it('shows an access error', async () => {
            getRows.mockResolvedValue({ status: 'ACCESS_ERROR', message: "This record isn't available to you." });
            const element = await mount();
            expect($(element, '[data-id="access-error"]').textContent).toContain("isn't available");
        });

        it('shows a retryable error when the request fails', async () => {
            getRows.mockRejectedValueOnce({ body: { message: 'Network down' } });
            const element = await mount();
            expect($(element, '[data-id="error"]').textContent).toContain('Network down');
            getRows.mockResolvedValue(okResponse());
            $(element, '[data-id="error"] lightning-button').click();
            await flush();
            expect($(element, 'lightning-datatable')).not.toBeNull();
        });

        it('reports hidden columns', async () => {
            getRows.mockResolvedValue(okResponse({ context: { omittedColumnCount: 2 } }));
            const element = await mount();
            expect($(element, '[data-id="omitted"]')).not.toBeNull();
        });
    });

    describe('search', () => {
        it('debounces, resets to page 1 and shows the no-match state', async () => {
            jest.useFakeTimers();
            const element = await mount();
            getRows.mockClear();
            getRows.mockResolvedValue(okResponse({ rows: [], totalCount: 0 }));

            const search = $(element, '[data-id="search"]');
            search.value = 'zzz';
            search.dispatchEvent(new CustomEvent('change'));
            jest.advanceTimersByTime(299);
            expect(getRows).not.toHaveBeenCalled();
            jest.advanceTimersByTime(1);
            await flush();

            expect(getRows).toHaveBeenCalledTimes(1);
            expect(lastRequest().searchTerm).toBe('zzz');
            expect(lastRequest().cursor).toBeNull();
            expect($(element, '[data-id="no-match"]')).not.toBeNull();
        });

        it('ignores a stale response that arrives after a newer one', async () => {
            jest.useFakeTimers();
            const element = await mount();
            let resolveSlow;
            getRows.mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolveSlow = resolve;
                    })
            );
            getRows.mockImplementationOnce(() => Promise.resolve(okResponse({ rows: [ROWS[1]], totalCount: 1 })));

            const search = $(element, '[data-id="search"]');
            search.value = 'a';
            search.dispatchEvent(new CustomEvent('change'));
            jest.advanceTimersByTime(300);
            search.value = 'bob';
            search.dispatchEvent(new CustomEvent('change'));
            jest.advanceTimersByTime(300);
            await flush();
            resolveSlow(okResponse({ rows: [ROWS[0]], totalCount: 1 }));
            await flush();

            const table = $(element, 'lightning-datatable');
            expect(table.data.map((r) => r.c_name)).toEqual(['Bob Ray']);
        });
    });

    describe('sorting and paging', () => {
        it('sorts the whole list on the server from page 1', async () => {
            getRows.mockResolvedValue(okResponse({ hasMore: true, nextCursor: 'cursor-2' }));
            const element = await mount();
            $(element, '[data-id="next"]').click();
            await flush();
            expect(lastRequest().cursor).toBe('cursor-2');

            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('sort', { detail: { fieldName: 'c_email', sortDirection: 'desc' } }));
            await flush();
            const request = lastRequest();
            expect(request.sortKey).toBe('c_email');
            expect(request.sortDirection).toBe('desc');
            expect(request.cursor).toBeNull();
            expect($(element, 'lightning-datatable').sortedBy).toBe('c_email');
        });

        it('maps a sort on a link column back to its key', async () => {
            const element = await mount();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('sort', { detail: { fieldName: 'c_name__url', sortDirection: 'asc' } }));
            await flush();
            expect(lastRequest().sortKey).toBe('c_name');
        });

        it('moves forward with the server cursor and back with the stored one', async () => {
            getRows.mockResolvedValueOnce(okResponse({ hasMore: true, nextCursor: 'cursor-2', totalCount: 3 }));
            const element = await mount();
            expect($(element, '[data-id="page"]').textContent).toBe('Page 1 of 2');
            expect($(element, '[data-id="prev"]').disabled).toBe(true);

            getRows.mockResolvedValueOnce(okResponse({ rows: [ROWS[1]], hasMore: false, totalCount: null }));
            $(element, '[data-id="next"]').click();
            await flush();
            expect(lastRequest().cursor).toBe('cursor-2');
            expect($(element, '[data-id="page"]').textContent).toBe('Page 2 of 2');
            expect($(element, '[data-id="next"]').disabled).toBe(true);
            expect($(element, 'lightning-datatable').rowNumberOffset).toBe(2);
            expect($(element, '[data-id="range"]').textContent).toBe('Showing 3–3 of 3');

            getRows.mockResolvedValueOnce(okResponse({ hasMore: true, nextCursor: 'cursor-2' }));
            $(element, '[data-id="prev"]').click();
            await flush();
            expect(lastRequest().cursor).toBeNull();
        });

        it('restarts from page 1 when the server reports a stale cursor', async () => {
            getRows.mockResolvedValueOnce(okResponse({ hasMore: true, nextCursor: 'cursor-2' }));
            const element = await mount();
            getRows.mockResolvedValueOnce({ status: 'STALE_CURSOR', message: 'The list changed.' });
            getRows.mockResolvedValueOnce(okResponse());
            $(element, '[data-id="next"]').click();
            await flush();
            expect(lastRequest().cursor).toBeNull();
            expect($(element, 'lightning-datatable')).not.toBeNull();
        });

        it('refresh() reloads page 1', async () => {
            const element = await mount();
            getRows.mockClear();
            await element.refresh();
            expect(getRows).toHaveBeenCalledTimes(1);
            expect(lastRequest().cursor).toBeNull();
        });

        it('reloads from page 1 when the parent record changes and clears selection', async () => {
            const element = await mount();
            const table = $(element, 'lightning-datatable');
            table.dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: [ROWS[0]] } }));
            await flush();
            expect($(element, '[data-id="bulk-delete"]').label).toBe('Delete selected (1)');
            element.recordId = '001000000000009AAA';
            await flush();
            expect(lastRequest().parentId).toBe('001000000000009AAA');
            expect($(element, '[data-id="bulk-delete"]').label).toBe('Delete selected (0)');
        });
    });

    describe('filters', () => {
        it('applies typed filters, shows pills, removes one and clears all', async () => {
            const element = await mount();
            const toggle = $(element, '[data-id="filter-toggle"]');
            const focusSpy = jest.spyOn(toggle, 'focus');
            toggle.click();
            await flush();
            const panel = $(element, 'c-filter-panel');
            expect(panel).not.toBeNull();
            expect(panel.columns.map((c) => c.key)).toEqual(['c_email', 'c_active']);

            panel.dispatchEvent(
                new CustomEvent('apply', {
                    detail: {
                        filters: [
                            { columnKey: 'c_email', operator: 'contains', value: 'example' },
                            { columnKey: 'c_active', operator: 'equals', value: 'false' }
                        ],
                        logic: 'OR'
                    }
                })
            );
            await flush();
            expect(lastRequest().filters).toHaveLength(2);
            expect(lastRequest().filterLogic).toBe('OR');
            expect(lastRequest().cursor).toBeNull();
            expect($(element, 'c-filter-panel')).toBeNull();
            expect(focusSpy).toHaveBeenCalled();

            const pills = element.shadowRoot.querySelectorAll('lightning-pill');
            expect([...pills].map((p) => p.label)).toEqual(['Email contains "example"', 'Active equals "False"']);

            pills[0].dispatchEvent(new CustomEvent('remove'));
            await flush();
            expect(lastRequest().filters).toEqual([{ columnKey: 'c_active', operator: 'equals', value: 'false' }]);

            $(element, '[data-id="clear-all"]').click();
            await flush();
            expect(lastRequest().filters).toEqual([]);
            expect(lastRequest().searchTerm).toBeNull();
            expect(element.shadowRoot.querySelectorAll('lightning-pill')).toHaveLength(0);
        });

        it('closes the panel on cancel and returns focus to the toggle', async () => {
            const element = await mount();
            const toggle = $(element, '[data-id="filter-toggle"]');
            const focusSpy = jest.spyOn(toggle, 'focus');
            toggle.click();
            await flush();
            $(element, 'c-filter-panel').dispatchEvent(new CustomEvent('cancel'));
            await flush();
            expect($(element, 'c-filter-panel')).toBeNull();
            expect(focusSpy).toHaveBeenCalled();
        });
    });

    describe('actions', () => {
        it('hides actions the user is not allowed to use', async () => {
            getRows.mockResolvedValue(okResponse({ context: { canCreate: false, canEdit: false, canDelete: false, canBulkDelete: false, flowApiName: null } }));
            const element = await mount();
            expect($(element, '[data-id="new"]')).toBeNull();
            expect($(element, '[data-id="flow"]')).toBeNull();
            expect($(element, '[data-id="bulk-delete"]')).toBeNull();
            const table = $(element, 'lightning-datatable');
            expect(table.hideCheckboxColumn).toBe(true);
            const actionCol = table.columns.find((c) => c.type === 'action');
            expect(actionCol.typeAttributes.rowActions.map((a) => a.name)).toEqual(['view']);
        });

        it('navigates to New with the parent lookup defaulted', async () => {
            const element = await mount();
            $(element, '[data-id="new"]').click();
            const call = getNavigateCalls()[0].pageReference;
            expect(call.type).toBe('standard__objectPage');
            expect(call.attributes).toEqual({ objectApiName: 'Contact', actionName: 'new' });
            expect(call.state.defaultFieldValues).toBe(`AccountId=${PARENT_ID}`);
            expect(call.state.navigationLocation).toBe('RELATED_LIST');
        });

        it('views a row', async () => {
            const element = await mount();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'view' }, row: ROWS[0] } }));
            const call = getNavigateCalls()[0].pageReference;
            expect(call.attributes.recordId).toBe(ROWS[0].id);
        });

        it('edits through the modal and refreshes after save', async () => {
            EditModal.open.mockResolvedValue('saved');
            const element = await mount();
            const toasts = captureToasts(element);
            getRows.mockClear();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'edit' }, row: ROWS[0] } }));
            await flush();
            expect(EditModal.open).toHaveBeenCalledWith(expect.objectContaining({ recordId: ROWS[0].id, objectApiName: 'Contact', fields: ['Email'] }));
            expect(getRows).toHaveBeenCalledTimes(1);
            expect(toasts[0].variant).toBe('success');
        });

        it('does not refresh when edit is cancelled', async () => {
            EditModal.open.mockResolvedValue('cancel');
            const element = await mount();
            getRows.mockClear();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'edit' }, row: ROWS[0] } }));
            await flush();
            expect(getRows).not.toHaveBeenCalled();
        });

        it('deletes one row after confirmation and restores focus to the heading', async () => {
            LightningConfirm.open.mockResolvedValue(true);
            deleteRecord.mockResolvedValue();
            const element = await mount();
            getRows.mockClear();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'delete' }, row: ROWS[1] } }));
            await flush();
            expect(LightningConfirm.open).toHaveBeenCalledWith(expect.objectContaining({ label: 'Delete Contact', theme: 'error' }));
            expect(deleteRecord).toHaveBeenCalledWith(ROWS[1].id);
            expect(getRows).toHaveBeenCalled();
            expect(element.shadowRoot.activeElement).toBe($(element, '[data-id="heading"]'));
        });

        it('reports a single delete failure without reloading', async () => {
            LightningConfirm.open.mockResolvedValue(true);
            deleteRecord.mockRejectedValue({ body: { message: 'Entity is locked' } });
            const element = await mount();
            const toasts = captureToasts(element);
            getRows.mockClear();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'delete' }, row: ROWS[1] } }));
            await flush();
            expect(getRows).not.toHaveBeenCalled();
            expect(toasts[0].variant).toBe('error');
            expect(toasts[0].message).toBe('Entity is locked');
        });

        it('does nothing when delete is not confirmed', async () => {
            LightningConfirm.open.mockResolvedValue(false);
            const element = await mount();
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'delete' }, row: ROWS[1] } }));
            await flush();
            expect(deleteRecord).not.toHaveBeenCalled();
        });
    });

    describe('bulk delete', () => {
        async function selectAll(element) {
            $(element, 'lightning-datatable').dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: ROWS } }));
            await flush();
        }

        it('sends one bounded request and reports a mixed outcome truthfully', async () => {
            LightningConfirm.open.mockResolvedValue(true);
            deleteRows.mockResolvedValue({
                status: 'OK',
                deletedCount: 1,
                failedCount: 1,
                results: [
                    { recordId: ROWS[0].id, success: true },
                    { recordId: ROWS[1].id, success: false, message: 'Record is locked.' }
                ]
            });
            const element = await mount();
            const toasts = captureToasts(element);
            await selectAll(element);
            expect($(element, '[data-id="bulk-delete"]').label).toBe('Delete selected (2)');
            expect($(element, 'lightning-datatable').maxRowSelection).toBe(2);

            getRows.mockResolvedValue(okResponse({ rows: [ROWS[1]], totalCount: 1 }));
            $(element, '[data-id="bulk-delete"]').click();
            await flush();

            expect(LightningConfirm.open.mock.calls[0][0].message).toContain('Delete 2 selected contacts on this page');
            expect(deleteRows).toHaveBeenCalledTimes(1);
            expect(deleteRows.mock.calls[0][0].request).toEqual({
                definitionKey: 'Account_Contacts',
                parentId: PARENT_ID,
                recordIds: [ROWS[0].id, ROWS[1].id]
            });
            expect(toasts[0].variant).toBe('warning');
            expect($(element, '[data-id="row-errors"]').textContent).toContain('Bob Ray: Record is locked.');
            expect($(element, 'lightning-datatable').selectedRows).toEqual([ROWS[1].id]); // failure stays selected
        });

        it('does not call the server when the confirmation is cancelled', async () => {
            LightningConfirm.open.mockResolvedValue(false);
            const element = await mount();
            await selectAll(element);
            $(element, '[data-id="bulk-delete"]').click();
            await flush();
            expect(deleteRows).not.toHaveBeenCalled();
        });

        it('shows the server refusal', async () => {
            LightningConfirm.open.mockResolvedValue(true);
            deleteRows.mockResolvedValue({ status: 'ACCESS_ERROR', message: "You don't have permission to delete several records from this list." });
            const element = await mount();
            const toasts = captureToasts(element);
            await selectAll(element);
            $(element, '[data-id="bulk-delete"]').click();
            await flush();
            expect(toasts[0].variant).toBe('error');
            expect(toasts[0].message).toContain("don't have permission");
        });
    });

    describe('flow', () => {
        it('launches the configured flow with recordId and refreshes on finish', async () => {
            FlowModal.open.mockResolvedValue('finished');
            const element = await mount({ flowTitle: 'Update contacts' });
            getRows.mockClear();
            const button = $(element, '[data-id="flow"]');
            expect(button.label).toBe('Update contacts');
            button.click();
            await flush();
            expect(FlowModal.open).toHaveBeenCalledWith(
                expect.objectContaining({
                    flowApiName: 'Contact_Flow',
                    inputVariables: [{ name: 'recordId', type: 'String', value: PARENT_ID }]
                })
            );
            expect(getRows).toHaveBeenCalledTimes(1);
        });

        it('does not refresh when the flow is closed without finishing', async () => {
            FlowModal.open.mockResolvedValue(undefined);
            const element = await mount();
            getRows.mockClear();
            $(element, '[data-id="flow"]').click();
            await flush();
            expect(getRows).not.toHaveBeenCalled();
        });

        it('reports a flow error', async () => {
            FlowModal.open.mockResolvedValue('error');
            const element = await mount();
            const toasts = captureToasts(element);
            $(element, '[data-id="flow"]').click();
            await flush();
            expect(toasts[0].variant).toBe('error');
        });
    });

    describe('settings', () => {
        it('resets column widths after a resize', async () => {
            const element = await mount();
            const table = $(element, 'lightning-datatable');
            table.dispatchEvent(new CustomEvent('columnresize', { detail: { columnWidths: [300, 200] } }));
            await flush();
            expect($(element, 'lightning-datatable').columns[0].initialWidth).toBe(300);
            $(element, '[data-id="settings"]').dispatchEvent(new CustomEvent('select', { detail: { value: 'resetWidths' } }));
            await flush();
            expect($(element, 'lightning-datatable').columns[0].initialWidth).toBeUndefined();
        });
    });
});
