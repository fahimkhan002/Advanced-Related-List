import { LightningElement, api } from 'lwc';
import { OPERATOR_LABELS, VALUELESS_OPERATORS } from 'c/arlUtils';

const MAX_FILTERS = 20;
const BOOLEAN_OPTIONS = [
    { label: 'True', value: 'true' },
    { label: 'False', value: 'false' }
];
const LOGIC_OPTIONS = [
    { label: 'All conditions (AND)', value: 'AND' },
    { label: 'Any condition (OR)', value: 'OR' }
];

let idCounter = 0;
const nextId = () => `f${++idCounter}`;

/**
 * Typed filter editor. Edits a draft; nothing is applied until the user clicks Apply.
 * Events: `apply` { filters: [{columnKey, operator, value}], logic }, `cancel`.
 */
export default class FilterPanel extends LightningElement {
    /** Filterable column metadata from the server: { key, label, filterType, operators, options }. */
    @api columns = [];
    @api logic = 'AND';

    draft = [];
    draftLogic = 'AND';
    _applied = [];

    @api
    get filters() {
        return this._applied;
    }
    set filters(value) {
        this._applied = Array.isArray(value) ? value : [];
        this.resetDraft();
    }

    logicOptions = LOGIC_OPTIONS;

    connectedCallback() {
        // Public properties are all set before connectedCallback, so columns are known here.
        this.draftLogic = this.logic === 'OR' ? 'OR' : 'AND';
        this.resetDraft();
    }

    resetDraft() {
        this.draft = this._applied.map((f) => ({ id: nextId(), columnKey: f.columnKey, operator: f.operator, value: f.value }));
        if (this.draft.length === 0) {
            this.draft = [this.emptyRow()];
        }
    }

    emptyRow() {
        const first = (this.columns || [])[0];
        return { id: nextId(), columnKey: first ? first.key : null, operator: first ? first.operators[0] : null, value: '' };
    }

    get fieldOptions() {
        return (this.columns || []).map((c) => ({ label: c.label, value: c.key }));
    }

    get hasColumns() {
        return (this.columns || []).length > 0;
    }

    get rows() {
        return this.draft.map((row, index) => {
            const column = (this.columns || []).find((c) => c.key === row.columnKey) || {};
            const filterType = column.filterType || 'text';
            const operators = column.operators || [];
            return {
                ...row,
                fieldLabel: `Field for condition ${index + 1}`,
                operatorLabel: `Operator for condition ${index + 1}`,
                valueLabel: `Value for condition ${index + 1}`,
                removeLabel: `Remove condition ${index + 1}`,
                operatorOptions: operators.map((op) => ({ label: OPERATOR_LABELS[op] || op, value: op })),
                needsValue: !VALUELESS_OPERATORS.has(row.operator),
                isText: filterType === 'text',
                isNumber: filterType === 'number',
                isDate: filterType === 'date',
                isChoice: filterType === 'picklist' || filterType === 'boolean',
                choiceOptions: filterType === 'boolean' ? BOOLEAN_OPTIONS : column.options || []
            };
        });
    }

    get addDisabled() {
        return this.draft.length >= MAX_FILTERS || !this.hasColumns;
    }

    updateRow(id, changes) {
        this.draft = this.draft.map((row) => (row.id === id ? { ...row, ...changes } : row));
    }

    handleFieldChange(event) {
        const column = (this.columns || []).find((c) => c.key === event.detail.value);
        this.updateRow(event.target.dataset.id, {
            columnKey: event.detail.value,
            operator: column ? column.operators[0] : null,
            value: ''
        });
    }

    handleOperatorChange(event) {
        const changes = { operator: event.detail.value };
        if (VALUELESS_OPERATORS.has(event.detail.value)) {
            changes.value = '';
        }
        this.updateRow(event.target.dataset.id, changes);
    }

    handleValueChange(event) {
        this.updateRow(event.target.dataset.id, { value: event.detail.value });
    }

    handleLogicChange(event) {
        this.draftLogic = event.detail.value;
    }

    handleAdd() {
        if (!this.addDisabled) {
            this.draft = [...this.draft, this.emptyRow()];
        }
    }

    handleRemove(event) {
        const id = event.currentTarget.dataset.id;
        this.draft = this.draft.filter((row) => row.id !== id);
        if (this.draft.length === 0) {
            this.draft = [this.emptyRow()];
        }
    }

    handleApply() {
        const inputs = [...this.template.querySelectorAll('[data-role="value"]')];
        const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!valid) {
            return;
        }
        const filters = this.draft
            .filter((row) => row.columnKey && row.operator && (VALUELESS_OPERATORS.has(row.operator) || String(row.value ?? '').trim() !== ''))
            .map((row) => ({
                columnKey: row.columnKey,
                operator: row.operator,
                value: VALUELESS_OPERATORS.has(row.operator) ? null : String(row.value).trim()
            }));
        this.dispatchEvent(new CustomEvent('apply', { detail: { filters, logic: this.draftLogic } }));
    }

    handleClearAll() {
        this.draft = [this.emptyRow()];
        this.dispatchEvent(new CustomEvent('apply', { detail: { filters: [], logic: this.draftLogic } }));
    }

    handleCancel() {
        this.resetDraft();
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleCancel();
        }
    }
}
