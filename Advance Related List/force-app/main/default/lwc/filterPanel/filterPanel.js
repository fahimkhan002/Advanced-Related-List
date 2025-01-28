import { LightningElement, api, track } from 'lwc';

export default class FilterPanel extends LightningElement {
    @api objectInfo;
    @api fields;
    @track filters = [];
    
    operators = [
        { label: 'equals', value: '=' },
        { label: 'not equal to', value: '!=' },
        { label: 'less than', value: '<' },
        { label: 'greater than', value: '>' },
        { label: 'contains', value: 'LIKE' },
        { label: 'does not contain', value: 'does not contain' },  // Note this exact value
        { label: 'starts with', value: 'STARTS' },
        { label: 'ends with', value: 'ENDS' }
    ];

    logicOperators = [
        { label: 'AND', value: 'AND' },
        { label: 'OR', value: 'OR' }
    ];

    connectedCallback() {
        // Add initial filter
        this.addFilter();
    }

    addFilter() {
        this.filters.push({
            id: this.generateId(),
            field: '',
            operator: '=',
            value: '',
            logicOperator: 'AND'
        });
    }

    removeFilter(event) {
        const index = this.filters.findIndex(filter => 
            filter.id === event.target.dataset.id
        );
        if (index > -1) {
            this.filters.splice(index, 1);
            this.dispatchFilterChange();
        }
    }

    handleFieldChange(event) {
        const filterId = event.target.dataset.id;
        const filter = this.filters.find(f => f.id === filterId);
        if (filter) {
            filter.field = event.detail.value;
            this.dispatchFilterChange();
        }
    }

    handleOperatorChange(event) {
        const filterId = event.target.dataset.id;
        const filter = this.filters.find(f => f.id === filterId);
        if (filter) {
            filter.operator = event.detail.value;
            this.dispatchFilterChange();
        }
    }

    handleValueChange(event) {
        const filterId = event.target.dataset.id;
        const filter = this.filters.find(f => f.id === filterId);
        if (filter) {
            filter.value = event.detail.value;
            this.dispatchFilterChange();
        }
    }

    handleLogicOperatorChange(event) {
        const filterId = event.target.dataset.id;
        const filter = this.filters.find(f => f.id === filterId);
        if (filter) {
            filter.logicOperator = event.detail.value;
            this.dispatchFilterChange();
        }
    }

    dispatchFilterChange() {
        const filterConditions = this.filters.map(filter => ({
            field: filter.field,
            operator: filter.operator,
            value: filter.value,
            logicOperator: filter.logicOperator
        }));

        this.dispatchEvent(new CustomEvent('filterchange', {
            detail: filterConditions
        }));
    }

    generateId() {
        return 'filter-' + Math.random().toString(36).substr(2, 9);
    }

    get fieldOptions() {
        return this.fields
            .filter(field => {
                // Get the field info from objectInfo
                const fieldInfo = this.objectInfo?.fields[field];
                
                // Skip if it's an address field
                if (!fieldInfo) return false;
                
                // Check if it's an address field - either by data type or field name pattern
                const isAddress = fieldInfo.dataType === 'Address' || 
                                this.isAddressField(field);
                
                return !isAddress;
            })
            .map(field => ({
                label: this.objectInfo?.fields[field]?.label || field,
                value: field
            }));
    }

    isAddressField(fieldName) {
        if (!fieldName) return false;
        
        // Check for standard address field patterns
        const isStandardAddress = fieldName.toLowerCase().endsWith('address') &&
            (fieldName.toLowerCase().includes('mailing') ||
             fieldName.toLowerCase().includes('shipping') ||
             fieldName.toLowerCase().includes('billing') ||
             fieldName.toLowerCase().includes('other'));

        // Check for custom address field pattern
        const isCustomAddress = fieldName.toLowerCase().endsWith('__c') && 
                              fieldName.toLowerCase().includes('address');

        return isStandardAddress || isCustomAddress;
    }

    get isFirstFilter() {
        return this.filters.length === 1;
    }
}