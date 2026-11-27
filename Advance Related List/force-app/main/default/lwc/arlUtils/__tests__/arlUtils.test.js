import { clampPageSize, describeFilter, reduceError, safeHexColor } from 'c/arlUtils';

describe('c/arlUtils', () => {
    it('describes filters with field, operator and value labels', () => {
        const columns = [
            { key: 'a', label: 'Stage', filterType: 'picklist', options: [{ label: 'Closed Won', value: 'won' }] },
            { key: 'b', label: 'Active', filterType: 'boolean' },
            { key: 'c', label: 'Email', filterType: 'text' }
        ];
        expect(describeFilter({ columnKey: 'a', operator: 'equals', value: 'won' }, columns)).toBe('Stage equals "Closed Won"');
        expect(describeFilter({ columnKey: 'b', operator: 'equals', value: 'true' }, columns)).toBe('Active equals "True"');
        expect(describeFilter({ columnKey: 'c', operator: 'isBlank', value: null }, columns)).toBe('Email is blank');
        expect(describeFilter({ columnKey: 'zz', operator: 'contains', value: 'x' }, columns)).toBe('zz contains "x"');
    });

    it('reduces Aura, LDS and JS errors to a message', () => {
        expect(reduceError({ body: { message: 'Apex says no' } })).toBe('Apex says no');
        expect(reduceError({ body: [{ message: 'a' }, { message: 'b' }] })).toBe('a, b');
        expect(reduceError({ body: { output: { errors: [{ message: 'Validation failed' }] } } })).toBe('Validation failed');
        expect(reduceError(new Error('boom'))).toBe('boom');
        expect(reduceError(undefined)).toBe('Something went wrong. Try again.');
    });

    it('accepts only hex colours', () => {
        expect(safeHexColor('#1589EE')).toBe('#1589EE');
        expect(safeHexColor('#fff')).toBe('#fff');
        expect(safeHexColor('red')).toBeUndefined();
        expect(safeHexColor('#fff; background:url(x)')).toBeUndefined();
        expect(safeHexColor(undefined)).toBeUndefined();
    });

    it('clamps page size to 1..100', () => {
        expect(clampPageSize('25')).toBe(25);
        expect(clampPageSize(0)).toBe(1);
        expect(clampPageSize(500)).toBe(100);
        expect(clampPageSize('abc')).toBe(10);
    });
});
