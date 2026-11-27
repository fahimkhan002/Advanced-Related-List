import { createElement } from 'lwc';
import ArlFieldPicker from 'c/arlFieldPicker';
import listFields from '@salesforce/apex/RelatedListBuilderController.listFields';

jest.mock('@salesforce/apex/RelatedListBuilderController.listFields', () => ({ default: jest.fn() }), { virtual: true });

const OPPORTUNITY_FIELDS = [
    { apiName: 'AccountId', label: 'Account ID', type: 'REFERENCE', canSearch: false, canFilter: false, canSort: false, canEdit: true, relationshipName: 'Account', targetObject: 'Account', targetLabel: 'Account' },
    { apiName: 'Amount', label: 'Amount', type: 'CURRENCY', canSearch: false, canFilter: true, canSort: true, canEdit: true },
    { apiName: 'Name', label: 'Opportunity Name', type: 'STRING', canSearch: true, canFilter: true, canSort: true, canEdit: true },
    { apiName: 'StageName', label: 'Stage', type: 'PICKLIST', canSearch: true, canFilter: true, canSort: false, canEdit: true }
];
const ACCOUNT_FIELDS = [{ apiName: 'Industry', label: 'Industry', type: 'PICKLIST', canSearch: true, canFilter: true, canSort: false, canEdit: true }];

function flush() {
    return Array.from({ length: 8 }).reduce((p) => p.then(() => undefined), Promise.resolve());
}

async function mount(props = {}) {
    const element = createElement('c-arl-field-picker', { is: ArlFieldPicker });
    Object.assign(element, { rootObject: 'Opportunity', rootLabel: 'Opportunities', usedPaths: ['Name'] }, props);
    document.body.appendChild(element);
    await flush();
    return element;
}

const $ = (el, s) => el.shadowRoot.querySelector(s);
const $$ = (el, s) => [...el.shadowRoot.querySelectorAll(s)];

describe('c-arl-field-picker', () => {
    beforeEach(() => {
        listFields.mockImplementation(({ objectApiName }) => Promise.resolve(objectApiName === 'Account' ? ACCOUNT_FIELDS : OPPORTUNITY_FIELDS));
    });
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists fields with what each can do and marks fields already added', async () => {
        const el = await mount();
        expect(listFields).toHaveBeenCalledWith({ objectApiName: 'Opportunity' });
        const items = $$(el, '[data-id="picker-list"] li');
        expect(items).toHaveLength(4);
        expect(items[1].textContent).toContain('Can filter, sort');
        expect(items[0].textContent).toContain('Display only');
        expect(items[2].textContent).toContain('Added'); // Name is already used
        expect(items[2].querySelector('[data-role="select"]')).toBeNull();
    });

    it('filters by label or API name', async () => {
        const el = await mount();
        const search = $(el, '[data-id="picker-search"]');
        search.value = 'stage';
        search.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect($$(el, '[data-id="picker-list"] li')).toHaveLength(1);
    });

    it('selects a direct field with its capabilities', async () => {
        const el = await mount();
        const handler = jest.fn();
        el.addEventListener('select', handler);
        $$(el, '[data-role="select"]').find((b) => b.dataset.api === 'Amount').click();
        expect(handler.mock.calls[0][0].detail).toEqual({
            path: 'Amount',
            labelHint: 'Amount',
            meta: { type: 'CURRENCY', canSearch: false, canFilter: true, canSort: true, canEdit: true }
        });
    });

    it('drills into a lookup, builds the relationship path and disallows editing', async () => {
        const el = await mount();
        const handler = jest.fn();
        el.addEventListener('select', handler);
        $(el, '[data-role="drill"]').click();
        await flush();
        expect(listFields).toHaveBeenLastCalledWith({ objectApiName: 'Account' });
        expect($(el, '[data-id="picker-heading"]').textContent).toBe('Choose a field from Account');
        expect($$(el, '.slds-breadcrumb__item').map((li) => li.textContent)).toEqual(['Opportunities', 'Account']);
        expect($(el, '[data-id="picker-list"] li').textContent).toContain('Account.Industry');
        $(el, '[data-role="select"]').click();
        expect(handler.mock.calls[0][0].detail.path).toBe('Account.Industry');
        expect(handler.mock.calls[0][0].detail.labelHint).toBe('Account: Industry');
        expect(handler.mock.calls[0][0].detail.meta.canEdit).toBe(false);

        $$(el, '.slds-breadcrumb__item a')[0].click();
        await flush();
        expect(listFields).toHaveBeenLastCalledWith({ objectApiName: 'Opportunity' });
    });

    it('cancels from the button and with Escape', async () => {
        const el = await mount();
        const handler = jest.fn();
        el.addEventListener('cancel', handler);
        $(el, '[data-id="picker-cancel"]').click();
        $(el, 'section').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        expect(handler).toHaveBeenCalledTimes(2);
    });

    it('shows a load error', async () => {
        listFields.mockRejectedValue({ body: { message: 'Object "X" was not found.' } });
        const el = await mount();
        expect($(el, '[role="alert"]').textContent).toBe('Object "X" was not found.');
    });
});
