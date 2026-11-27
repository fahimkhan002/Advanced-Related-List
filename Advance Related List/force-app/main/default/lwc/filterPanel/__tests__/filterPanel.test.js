import { createElement } from 'lwc';
import FilterPanel from 'c/filterPanel';

const COLUMNS = [
    { key: 'c_email', label: 'Email', filterType: 'text', operators: ['equals', 'contains', 'isBlank'] },
    { key: 'c_amount', label: 'Amount', filterType: 'number', operators: ['equals', 'greaterThan', 'isBlank'] },
    { key: 'c_close', label: 'Close Date', filterType: 'date', operators: ['equals', 'lessThan'] },
    {
        key: 'c_stage',
        label: 'Stage',
        filterType: 'picklist',
        operators: ['equals', 'notEquals'],
        options: [
            { label: 'Open', value: 'open' },
            { label: 'Won', value: 'won' }
        ]
    },
    { key: 'c_active', label: 'Active', filterType: 'boolean', operators: ['equals'] }
];

function flush() {
    // Drain chained microtasks without timers (tests also use fake timers).
    return Array.from({ length: 5 }).reduce((p) => p.then(() => undefined), Promise.resolve());
}

function mount(props = {}) {
    const element = createElement('c-filter-panel', { is: FilterPanel });
    Object.assign(element, { columns: COLUMNS }, props);
    document.body.appendChild(element);
    return element;
}

const all = (element, selector) => [...element.shadowRoot.querySelectorAll(selector)];
const one = (element, selector) => element.shadowRoot.querySelector(selector);

function change(target, value) {
    target.value = value;
    target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-filter-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('starts with one condition on the first filterable field with labelled controls', () => {
        const element = mount();
        const field = one(element, '[data-role="field"]');
        expect(field.value).toBe('c_email');
        expect(field.label).toBe('Field for condition 1');
        expect(one(element, '[data-role="operator"]').options.map((o) => o.label)).toEqual(['equals', 'contains', 'is blank']);
        expect(one(element, '[data-role="value"]').type).toBe('text');
    });

    it('switches the value control by field type', async () => {
        const element = mount();
        change(one(element, '[data-role="field"]'), 'c_amount');
        await flush();
        expect(one(element, '[data-role="value"]').type).toBe('number');
        change(one(element, '[data-role="field"]'), 'c_close');
        await flush();
        expect(one(element, '[data-role="value"]').type).toBe('date');
        change(one(element, '[data-role="field"]'), 'c_stage');
        await flush();
        expect(one(element, '[data-role="value"]').options).toEqual(COLUMNS[3].options);
        change(one(element, '[data-role="field"]'), 'c_active');
        await flush();
        expect(one(element, '[data-role="value"]').options.map((o) => o.value)).toEqual(['true', 'false']);
    });

    it('hides the value for blank operators and applies with the chosen logic', async () => {
        const element = mount();
        const handler = jest.fn();
        element.addEventListener('apply', handler);

        change(one(element, '[data-role="operator"]'), 'isBlank');
        await flush();
        expect(one(element, '[data-role="value"]')).toBeNull();

        one(element, '[data-role="add"]').click();
        await flush();
        const fields = all(element, '[data-role="field"]');
        change(fields[1], 'c_amount');
        await flush();
        change(all(element, '[data-role="operator"]')[1], 'greaterThan');
        await flush();
        change(one(element, '[data-role="value"]'), ' 100 ');
        await flush();
        one(element, 'lightning-radio-group').dispatchEvent(new CustomEvent('change', { detail: { value: 'OR' } }));
        await flush();

        // The sfdx-lwc-jest stub returns undefined; the real component returns a boolean.
        all(element, '[data-role="value"]').forEach((input) => {
            input.reportValidity = jest.fn(() => true);
        });
        one(element, '[data-role="apply"]').click();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            filters: [
                { columnKey: 'c_email', operator: 'isBlank', value: null },
                { columnKey: 'c_amount', operator: 'greaterThan', value: '100' }
            ],
            logic: 'OR'
        });
    });

    it('does not apply when a required value is invalid', () => {
        const element = mount();
        const handler = jest.fn();
        element.addEventListener('apply', handler);
        one(element, '[data-role="value"]').reportValidity = jest.fn(() => false);
        one(element, '[data-role="apply"]').click();
        expect(handler).not.toHaveBeenCalled();
    });

    it('removes a condition and keeps at least one row', async () => {
        const element = mount();
        one(element, '[data-role="add"]').click();
        await flush();
        expect(all(element, 'li')).toHaveLength(2);
        all(element, '[data-role="remove"]')[0].click();
        await flush();
        expect(all(element, 'li')).toHaveLength(1);
        one(element, '[data-role="remove"]').click();
        await flush();
        expect(all(element, 'li')).toHaveLength(1);
    });

    it('limits the number of conditions to 20', async () => {
        const element = mount();
        await Array.from({ length: 25 }).reduce(
            (p) =>
                p.then(() => {
                    one(element, '[data-role="add"]').click();
                    return flush();
                }),
            Promise.resolve()
        );
        expect(all(element, 'li')).toHaveLength(20);
        expect(one(element, '[data-role="add"]').disabled).toBe(true);
    });

    it('shows applied filters, clears all, and cancels with Escape', async () => {
        const element = mount({ filters: [{ columnKey: 'c_stage', operator: 'equals', value: 'won' }], logic: 'OR' });
        await flush();
        expect(one(element, '[data-role="field"]').value).toBe('c_stage');
        expect(one(element, 'lightning-radio-group').value).toBe('OR');

        const applied = jest.fn();
        element.addEventListener('apply', applied);
        one(element, '[data-role="clear"]').click();
        expect(applied.mock.calls[0][0].detail.filters).toEqual([]);

        const cancelled = jest.fn();
        element.addEventListener('cancel', cancelled);
        one(element, 'section').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        expect(cancelled).toHaveBeenCalledTimes(1);
    });

    it('explains when nothing can be filtered', () => {
        const element = mount({ columns: [] });
        expect(one(element, 'p').textContent).toBe('No fields in this list can be filtered.');
    });
});
