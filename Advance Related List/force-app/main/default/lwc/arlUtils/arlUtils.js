/**
 * Shared, framework-free helpers for the Tekenable Advance Related List components.
 */

export const OPERATOR_LABELS = {
    equals: 'equals',
    notEquals: 'does not equal',
    contains: 'contains',
    notContains: 'does not contain',
    startsWith: 'starts with',
    endsWith: 'ends with',
    lessThan: 'is before / less than',
    greaterThan: 'is after / greater than',
    lessOrEqual: 'is on or before / at most',
    greaterOrEqual: 'is on or after / at least',
    isBlank: 'is blank',
    isNotBlank: 'is not blank'
};

export const VALUELESS_OPERATORS = new Set(['isBlank', 'isNotBlank']);

/**
 * Human-readable description of one applied filter, for pills and screen readers.
 * @param {object} filter { columnKey, operator, value }
 * @param {Array} columns column metadata from the server
 * @returns {string}
 */
export function describeFilter(filter, columns) {
    const column = (columns || []).find((c) => c.key === filter.columnKey);
    const fieldLabel = column ? column.label : filter.columnKey;
    const operatorLabel = OPERATOR_LABELS[filter.operator] || filter.operator;
    if (VALUELESS_OPERATORS.has(filter.operator)) {
        return `${fieldLabel} ${operatorLabel}`;
    }
    let valueLabel = filter.value;
    if (column && column.filterType === 'picklist' && Array.isArray(column.options)) {
        const option = column.options.find((o) => o.value === filter.value);
        valueLabel = option ? option.label : filter.value;
    } else if (column && column.filterType === 'boolean') {
        valueLabel = filter.value === 'true' ? 'True' : 'False';
    }
    return `${fieldLabel} ${operatorLabel} "${valueLabel}"`;
}

/**
 * Reduces Aura/LDS/JS errors to a user-safe message.
 * @param {*} error
 * @returns {string}
 */
export function reduceError(error) {
    if (!error) {
        return 'Something went wrong. Try again.';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((e) => e.message).filter(Boolean).join(', ') || 'Something went wrong. Try again.';
    }
    if (error.body) {
        if (error.body.output && Array.isArray(error.body.output.errors) && error.body.output.errors.length) {
            return error.body.output.errors.map((e) => e.message).join(', ');
        }
        if (typeof error.body.message === 'string' && error.body.message) {
            return error.body.message;
        }
    }
    if (typeof error.message === 'string' && error.message) {
        return error.message;
    }
    return 'Something went wrong. Try again.';
}

/**
 * Accepts only CSS hex colours so App Builder input cannot inject style declarations.
 * @param {string} value
 * @returns {string|undefined}
 */
export function safeHexColor(value) {
    return typeof value === 'string' && /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value.trim()) ? value.trim() : undefined;
}

/**
 * Clamps a page size to the server-supported range.
 * @param {*} value
 * @returns {number}
 */
export function clampPageSize(value) {
    const n = parseInt(value, 10);
    if (Number.isNaN(n)) {
        return 10;
    }
    return Math.min(100, Math.max(1, n));
}
