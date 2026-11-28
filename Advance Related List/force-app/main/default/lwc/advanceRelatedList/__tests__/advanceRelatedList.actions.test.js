import { createElement } from 'lwc';
import AdvanceRelatedList from 'c/advanceRelatedList';
import getRows from '@salesforce/apex/RelatedListController.getRows';
import FlowModal from 'c/arlFlowModal';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import { getNavigateCalls, resetNavigateCalls } from 'lightning/navigation';

jest.mock('@salesforce/apex/RelatedListController.getRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListController.deleteRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('c/arlFlowModal', () => ({ __esModule: true, default: { open: jest.fn() } }));
jest.mock('@salesforce/user/Id', () => ({ __esModule: true, default: '005000000000001AAA' }), { virtual: true });

const PARENT_ID = '001000000000001AAA';
const COLUMNS = [
    { key: 'c_name', label: 'Name', type: 'name', visible: true, sortable: true, searchable: true },
    { key: 'c_stage', label: 'Stage', type: 'picklist', visible: true, filterable: true, filterType: 'picklist', operators: ['equals'], options: [{ label: 'Won', value: 'won' }] },
    { key: 'c_amt', label: 'Amount', type: 'currency', visible: true, sortable: true }
];
const ROWS = [{ id: '006000000000001AAA', c_name: 'Deal 1', c_name__id: '006000000000001AAA' }];
const ACTIONS = [
    { key: 'review', type: 'flow', target: 'Account_Review', label: 'Review account', placement: 'list' },
    { key: 'forecast', type: 'flow', target: 'Forecast_Note', label: 'Forecast note', placement: 'list' },
    { key: 'task', type: 'quickAction', target: 'Global.NewTask', label: 'New Task', placement: 'list' },
    { key: 'check', type: 'flow', target: 'Deal_Check', label: 'Deal check', placement: 'row' },
    { key: 'call', type: 'quickAction', target: 'Global.LogACall', label: 'Log a Call', placement: 'row' }
];

function response(overrides = {}) {
    const { context, ...rest } = overrides;
    return {
        status: 'OK',
        columns: COLUMNS,
        rows: ROWS,
        totalCount: 1,
        hasMore: false,
        ...rest,
        context: {
            mode: 'definition',
            definitionKey: 'Account_Deals',
            objectApiName: 'Opportunity',
            objectLabel: 'Opportunity',
            objectLabelPlural: 'Opportunities',
            lookupField: 'AccountId',
            canCreate: true,
            canEdit: true,
            canDelete: true,
            canBulkDelete: false,
            actions: ACTIONS,
            editFields: [],
            sortKey: 'c_name',
            sortDirection: 'asc',
            maxDeleteBatch: 100,
            ...(context || {})
        }
    };
}

function flush() {
    return Array.from({ length: 12 }).reduce((p) => p.then(() => undefined), Promise.resolve());
}

async function mount(props = {}) {
    const el = createElement('c-advance-related-list', { is: AdvanceRelatedList });
    Object.assign(el, { recordId: PARENT_ID, listDefinition: 'Account_Deals', recordsPerPage: 5 }, props);
    document.body.appendChild(el);
    await flush();
    return el;
}

const $ = (el, s) => el.shadowRoot.querySelector(s);
const $$ = (el, s) => [...el.shadowRoot.querySelectorAll(s)];
const storedKeys = () => Object.keys(window.localStorage).filter((k) => k.startsWith('arl:v1:'));

describe('c-advance-related-list actions and remembered filters', () => {
    beforeEach(() => {
        getRows.mockResolvedValue(response());
        resetNavigateCalls();
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        window.localStorage.clear();
    });

    describe('configured actions', () => {
        it('shows the first two header actions as buttons and the rest under More', async () => {
            const el = await mount();
            const buttons = $$(el, '[data-id="header-action"]');
            expect(buttons.map((b) => b.label)).toEqual(['Review account', 'Forecast note']);
            const more = $(el, '[data-id="more-actions"]');
            expect(more).not.toBeNull();
            expect([...more.querySelectorAll('lightning-menu-item')].map((i) => i.label)).toEqual(['New Task']);
        });

        it('runs a header flow for the parent record and refreshes when it finishes', async () => {
            FlowModal.open.mockResolvedValue('finished');
            const el = await mount();
            getRows.mockClear();
            $$(el, '[data-id="header-action"]')[1].click();
            await flush();
            expect(FlowModal.open).toHaveBeenCalledWith(
                expect.objectContaining({ flowApiName: 'Forecast_Note', label: 'Forecast note', inputVariables: [{ name: 'recordId', type: 'String', value: PARENT_ID }] })
            );
            expect(getRows).toHaveBeenCalledTimes(1);
        });

        it('opens a header quick action for the parent record', async () => {
            const el = await mount();
            $(el, '[data-id="more-actions"]').dispatchEvent(new CustomEvent('select', { detail: { value: 'task' } }));
            await flush();
            expect(getNavigateCalls()[0].pageReference).toEqual({
                type: 'standard__quickAction',
                attributes: { apiName: 'Global.NewTask' },
                state: { recordId: PARENT_ID }
            });
        });

        it('adds row actions to each row menu and runs them for that row', async () => {
            FlowModal.open.mockResolvedValue(undefined);
            const el = await mount();
            const table = $(el, 'lightning-datatable');
            const rowActions = table.columns.find((c) => c.type === 'action').typeAttributes.rowActions;
            expect(rowActions.map((a) => a.name)).toEqual(['view', 'edit', 'delete', 'action:check', 'action:call']);

            table.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'action:check' }, row: ROWS[0] } }));
            await flush();
            expect(FlowModal.open).toHaveBeenCalledWith(expect.objectContaining({ flowApiName: 'Deal_Check', inputVariables: [{ name: 'recordId', type: 'String', value: ROWS[0].id }] }));

            table.dispatchEvent(new CustomEvent('rowaction', { detail: { action: { name: 'action:call' }, row: ROWS[0] } }));
            await flush();
            expect(getNavigateCalls()[0].pageReference.state.recordId).toBe(ROWS[0].id);
            expect(getNavigateCalls()[0].pageReference.attributes.apiName).toBe('Global.LogACall');
        });

        it('follows the admin order and Show as choice, joined like standard actions with a ▾ overflow', async () => {
            getRows.mockResolvedValue(
                response({
                    context: {
                        actions: [
                            { key: 'new', type: 'standard', target: 'new', label: 'Add deal', placement: 'list', display: 'button' },
                            { key: 'review', type: 'flow', target: 'Account_Review', label: 'Review account', placement: 'list', display: 'menu' },
                            { key: 'forecast', type: 'flow', target: 'Forecast_Note', label: 'Forecast note', placement: 'list', display: 'button' },
                            { key: 'task', type: 'quickAction', target: 'Global.NewTask', label: 'New Task', placement: 'list', display: 'button' }
                        ]
                    }
                })
            );
            const el = await mount();
            const buttons = $$(el, 'lightning-button').filter((b) => b.dataset.key);
            expect(buttons.map((b) => b.label)).toEqual(['Add deal', 'Forecast note', 'New Task']);
            expect(buttons[0].dataset.id).toBe('new');
            expect([...$(el, '[data-id="more-actions"]').querySelectorAll('lightning-menu-item')].map((i) => i.label)).toEqual(['Review account']);
            // joined like the standard record actions, with a ▾ overflow at the end of the same group
            const group = $(el, '[data-id="header-actions"]');
            expect(group.tagName.toLowerCase()).toBe('lightning-button-group');
            expect([...group.children].map((c) => c.dataset.id)).toEqual(['new', 'header-action', 'header-action', 'more-actions']);
            const more = $(el, '[data-id="more-actions"]');
            expect(more.iconName).toBe('utility:down');
            expect(more.label).toBeUndefined();
            expect(more.alternativeText).toBe('More actions');

            buttons[0].click();
            expect(getNavigateCalls()[0].pageReference.attributes).toEqual({ objectApiName: 'Opportunity', actionName: 'new' });
        });

        it('shows no New button when the list has none', async () => {
            const el = await mount();
            expect($(el, '[data-id="new"]')).toBeNull();
        });

        it('uses the Flow Modal Title for the legacy single flow', async () => {
            getRows.mockResolvedValue(response({ context: { actions: [{ key: 'flow', type: 'flow', target: 'Old_Flow', label: null, placement: 'list' }] } }));
            const el = await mount({ flowTitle: 'Update contacts' });
            expect($(el, '[data-id="header-action"]').label).toBe('Update contacts');
            expect($(el, '[data-id="more-actions"]')).toBeNull();
        });

        it('refreshes when the record page refreshes and unregisters on removal', async () => {
            const el = await mount();
            expect(registerRefreshHandler).toHaveBeenCalled();
            const handler = registerRefreshHandler.mock.calls[0][1];
            getRows.mockClear();
            await expect(handler()).resolves.toBe(true);
            expect(getRows).toHaveBeenCalledTimes(1);
            document.body.removeChild(el);
            expect(unregisterRefreshHandler).toHaveBeenCalled();
        });
    });

    describe('remembered filters and sort', () => {
        async function applyStageFilter(el) {
            $(el, '[data-id="filter-toggle"]').click();
            await flush();
            $(el, 'c-filter-panel').dispatchEvent(new CustomEvent('apply', { detail: { filters: [{ columnKey: 'c_stage', operator: 'equals', value: 'won' }], logic: 'OR' } }));
            await flush();
        }

        it('keeps filters across a page refresh (remount) for the same user and list', async () => {
            const first = await mount();
            await applyStageFilter(first);
            expect(storedKeys()).toHaveLength(1);
            expect(storedKeys()[0]).toContain('def:Account_Deals');
            expect($(first, '[data-id="remembered"]').textContent).toBe('Kept for your next visit');
            document.body.removeChild(first);

            getRows.mockClear();
            const second = await mount();
            const request = getRows.mock.calls[0][0].request;
            expect(request.filters).toEqual([{ columnKey: 'c_stage', operator: 'equals', value: 'won' }]);
            expect(request.filterLogic).toBe('OR');
            expect($$(second, 'lightning-pill').map((p) => p.label)).toEqual(['Stage equals "Won"']);
        });

        it('keeps the sort and applies it on the first request', async () => {
            const first = await mount();
            $(first, 'lightning-datatable').dispatchEvent(new CustomEvent('sort', { detail: { fieldName: 'c_amt', sortDirection: 'desc' } }));
            await flush();
            document.body.removeChild(first);
            getRows.mockClear();
            await mount();
            const request = getRows.mock.calls[0][0].request;
            expect(request.sortKey).toBe('c_amt');
            expect(request.sortDirection).toBe('desc');
        });

        it('forgets filters on Clear all', async () => {
            const el = await mount();
            await applyStageFilter(el);
            $(el, '[data-id="clear-all"]').click();
            await flush();
            expect(storedKeys()).toHaveLength(0);
        });

        it('forgets saved filters that no longer fit the list and reloads without them', async () => {
            const key = 'arl:v1:005000000000001AAA:def:Account_Deals';
            window.localStorage.setItem(key, JSON.stringify({ filters: [{ columnKey: 'c_gone', operator: 'equals', value: 'x' }], logic: 'AND' }));
            getRows.mockResolvedValueOnce({ status: 'INPUT_ERROR', message: "One of the filters uses a field that can't be filtered." }).mockResolvedValue(response());
            const el = await mount();
            const sent = getRows.mock.calls.map((c) => c[0].request.filters.length);
            expect(sent).toEqual([1, 0]);
            expect(window.localStorage.getItem(key)).toBeNull();
            expect($(el, '[data-id="remember-notice"]').textContent).toContain('no longer match');
            expect($(el, 'lightning-datatable')).not.toBeNull();
            expect($(el, '[data-id="input-error"]')).toBeNull();
        });

        it('ignores corrupt saved data', async () => {
            window.localStorage.setItem('arl:v1:005000000000001AAA:def:Account_Deals', '{not json');
            await mount();
            expect(getRows.mock.calls[0][0].request.filters).toEqual([]);
        });

        it('does not store anything when the page turns it off', async () => {
            const el = await mount({ disableSavedFilters: true });
            await applyStageFilter(el);
            expect(storedKeys()).toHaveLength(0);
            expect($(el, '[data-id="remembered"]')).toBeNull();
        });

        it('keeps lists apart: a different definition does not get these filters', async () => {
            const first = await mount();
            await applyStageFilter(first);
            document.body.removeChild(first);
            getRows.mockClear();
            await mount({ listDefinition: 'Other_List' });
            expect(getRows.mock.calls[0][0].request.filters).toEqual([]);
        });
    });
});
