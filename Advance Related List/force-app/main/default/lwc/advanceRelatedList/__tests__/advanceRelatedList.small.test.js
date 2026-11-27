import { createElement } from 'lwc';
import AdvanceRelatedList from 'c/advanceRelatedList';
import getRows from '@salesforce/apex/RelatedListController.getRows';
import EditModal from 'c/arlEditModal';
import { getNavigateCalls, resetNavigateCalls } from 'lightning/navigation';

jest.mock('@salesforce/client/formFactor', () => ({ __esModule: true, default: 'Small' }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListController.getRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RelatedListController.deleteRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('c/arlEditModal', () => ({ __esModule: true, default: { open: jest.fn() } }));

const RESPONSE = {
    status: 'OK',
    context: {
        mode: 'definition',
        definitionKey: 'Account_Contacts',
        objectApiName: 'Contact',
        objectLabel: 'Contact',
        objectLabelPlural: 'Contacts',
        lookupField: 'AccountId',
        canCreate: true,
        canEdit: true,
        canDelete: false,
        canBulkDelete: true,
        editFields: [],
        sortKey: 'c_name',
        sortDirection: 'asc',
        omittedColumnCount: 0,
        maxDeleteBatch: 100
    },
    columns: [
        { key: 'c_name', label: 'Name', type: 'name', visible: true, sortable: true },
        { key: 'c_email', label: 'Email', type: 'email', visible: true, sortable: true },
        { key: 'c_active', label: 'Active', type: 'boolean', visible: true },
        { key: 'c_amt', label: 'Amount', type: 'currency', visible: true }
    ],
    rows: [{ id: '003000000000001AAA', c_name: 'Ann Lee', c_name__id: '003000000000001AAA', c_email: 'ann@example.com', c_active: false, c_amt: 1234.5 }],
    totalCount: 1,
    hasMore: false
};

function flush() {
    // Drain chained microtasks without timers (tests also use fake timers).
    return Array.from({ length: 10 }).reduce((p) => p.then(() => undefined), Promise.resolve());
}

describe('c-advance-related-list on a phone', () => {
    let element;

    beforeEach(async () => {
        resetNavigateCalls();
        getRows.mockResolvedValue(RESPONSE);
        element = createElement('c-advance-related-list', { is: AdvanceRelatedList });
        element.recordId = '001000000000001AAA';
        element.listDefinition = 'Account_Contacts';
        document.body.appendChild(element);
        await flush();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a card list instead of a datatable', () => {
        expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
        const cards = element.shadowRoot.querySelectorAll('[data-id="cards"] > li');
        expect(cards).toHaveLength(1);
        expect(cards[0].querySelector('a').textContent).toBe('Ann Lee');
        const details = [...cards[0].querySelectorAll('dd')].map((d) => d.textContent);
        expect(details).toEqual(['ann@example.com', 'No', '1,234.5']);
    });

    it('does not offer bulk selection or the column settings menu', () => {
        expect(element.shadowRoot.querySelector('[data-id="bulk-delete"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="settings"]')).toBeNull();
    });

    it('offers sorting through labelled comboboxes', async () => {
        const sort = element.shadowRoot.querySelector('[data-id="small-sort"]');
        const [field, direction] = sort.querySelectorAll('lightning-combobox');
        expect(field.label).toBe('Sort by');
        expect(field.options.map((o) => o.value)).toEqual(['c_name', 'c_email']);
        direction.dispatchEvent(new CustomEvent('change', { detail: { value: 'desc' } }));
        await flush();
        const request = getRows.mock.calls[getRows.mock.calls.length - 1][0].request;
        expect(request.sortKey).toBe('c_name');
        expect(request.sortDirection).toBe('desc');
    });

    it('opens a record from its card title and actions from the menu', async () => {
        const card = element.shadowRoot.querySelector('[data-id="cards"] > li');
        card.querySelector('a').click();
        expect(getNavigateCalls()[0].pageReference.attributes.recordId).toBe('003000000000001AAA');

        const menu = card.querySelector('lightning-button-menu');
        expect(menu.alternativeText).toBe('Actions for Ann Lee');
        const items = [...menu.querySelectorAll('lightning-menu-item')].map((i) => i.value);
        expect(items).toEqual(['view', 'edit']); // delete not allowed in this context
        EditModal.open.mockResolvedValue(undefined);
        menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'edit' } }));
        await flush();
        expect(EditModal.open).toHaveBeenCalledWith(expect.objectContaining({ recordId: '003000000000001AAA', fields: [] }));
    });
});
