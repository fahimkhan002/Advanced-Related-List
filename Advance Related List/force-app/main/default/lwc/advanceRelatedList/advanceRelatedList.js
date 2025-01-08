import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecords from '@salesforce/apex/RelatedListController.getRecords';
import deleteRecord from '@salesforce/apex/RelatedListController.deleteRecord';

// Define constants at the top level
const FIXED_WIDTH = {
    number: 60,
    action: 80
};

const actions = [
    { label: 'View', name: 'view', iconName: 'utility:preview' },
    { label: 'Edit', name: 'edit', iconName: 'utility:edit' },
    { label: 'Delete', name: 'delete', iconName: 'utility:delete' }
];


export default class AdvanceRelatedList extends NavigationMixin(LightningElement) {
    @api childObjectApiName;
    @api parentObjectApiName;
    // Add objectInfo property
    @track objectInfo;
    @api parentLookupField;
    @api recordId;
    @api fieldsToDisplay = '';
    @api columnLabels = '';
    @api searchableFields = '';
    @api recordsPerPage = 10;
    @api flowName;
    @api flowTitle = 'Run Flow';
    @api listTitle;
    @api sortableFields = '';
    @api customIconName;
    @api iconBackgroundColor;

    @track data = [];
    @track columns = [];
    @track filteredData = [];
    @track pageNumber = 1;
    @track totalPages = 0;
    @track isLoading = false;
    @track error;
    @track wiredRecordResult;
    @track childObjectLabel;
    @track selectedRows = [];
    @track showFlowModal = false;
    @track fieldLabelsMap = {};
    @track sortedBy;
    @track sortedDirection = 'asc';
    @track showEditModal = false;
    @track showDeleteModal = false;
    @track selectedRecordId;
    @track flowKey = Date.now(); // Add this at the top with other track properties
    // Add these track properties
    @track flowInputVariables = [];
    @track originalData = [];
    @track searchTerm = '';
    @track debouncedSearchTerm = '';
    searchTimeout;
    @track columnWidths = {};
    @track showSettingsMenu = false;
    @track defaultColumnWidth = 250; // Default width for columns

    get hasIcon() {
        return this.customIconName || this.objectIconName;
    }

    get iconName() {
        return this.customIconName || this.objectIconName || 'standard:custom';
    }

    get iconStyle() {
        return `background-color: ${this.iconBackgroundColor || '#f4b400'}`;
    }

    get fieldsArray() {
        return this.fieldsToDisplay.split(',').map(field => field.trim());
    }

    get sortableFieldsArray() {
        return this.sortableFields ? this.sortableFields.split(',').map(field => field.trim()) : [];
    }

    // Add columnLabelsArray getter if not exists
    get columnLabelsArray() {
        return this.columnLabels ? this.columnLabels.split(',').map(label => label.trim()) : [];
    }

    get searchableFieldsArray() {
        return this.searchableFields.split(',').map(field => field.trim());
    }

    get displayTitle() {
        const totalRecords = this.wiredRecordResult?.data?.totalRecords || 0;
        return `${this.listTitle || `Related ${this.childObjectLabel}`} (${totalRecords})`;
    }

    get hasFlowName() {
        return this.flowName && this.flowName.trim().length > 0;
    }

    get editFormFields() {
        return this.editableFields?.map(field => field.fieldApiName) || [];
    }

    // Update the wire service for object info
    @wire(getObjectInfo, { objectApiName: '$childObjectApiName' })
    wiredObjectInfo({ error, data }) {
        if (data) {
            this.objectInfo = data;
            this.childObjectLabel = data.label;
            this.objectIconName = this.customIconName || data.themeInfo?.iconUrl;
            
            // Get all fields metadata for edit form
            const fields = data.fields;
            this.editableFields = Object.keys(fields)
                .filter(fieldApi => {
                    const field = fields[fieldApi];
                    return field.updateable && !field.computed;
                })
                .map(fieldApi => ({
                    fieldApiName: fieldApi,
                    required: fields[fieldApi].required,
                    label: fields[fieldApi].label
                }));
                
            this.initializeColumns();
        } else if (error) {
            console.error('Error loading object info:', error);
        }
    }

            // Updated initializeColumns method
            initializeColumns() {
                const columnCount = this.fieldsArray.length;
                
                // Calculate available width for data columns
                const totalFixedWidth = FIXED_WIDTH.number + FIXED_WIDTH.action;
                let columnWidth;

                // Get container width
                const container = this.template.querySelector('.table-container');
                const availableWidth = container ? container.offsetWidth : 1200;

                if (columnCount <= 4) {
                    // For 5 or fewer columns, calculate width to fit container
                    columnWidth = Math.floor((availableWidth - totalFixedWidth) / columnCount);
                } else {
                    // For more than 5 columns, use fixed width
                    columnWidth = 255; // Fixed width to ensure scrolling
                }

                // Initialize the columns array
                this.columns = [
                    // Row Number Column
                    {
                        label: '#',
                        fieldName: 'rowNumber',
                        type: 'number',
                        sortable: false,
                        fixedWidth: FIXED_WIDTH.number,
                        initialWidth: FIXED_WIDTH.number
                    },
                    
                    // Data Columns
                    ...this.fieldsArray.map((field, index) => {
                        const isNameField = field.toLowerCase() === 'name';
                        const isLookupField = field.includes('.');
                        const isEmailField = field.toLowerCase().includes('email');
                        const isPhoneField = field.toLowerCase().includes('phone');
                        const isDateField = this.objectInfo?.fields[field]?.dataType === 'datetime' || 
                                        this.objectInfo?.fields[field]?.dataType === 'date';

                        let fieldConfig = {
                            label: this.getColumnLabel(field, index),
                            fieldName: isNameField ? 'nameUrl' : field,
                            sortable: this.sortableFieldsArray.includes(field),
                            wrapText: true,
                            initialWidth: this.columnWidths[field] || columnWidth
                        };

                        // Add specific configurations based on field type
                        if (isNameField) {
                            fieldConfig.type = 'url';
                            fieldConfig.typeAttributes = {
                                label: { fieldName: 'Name' },
                                target: '_self'
                            };
                        } else if (isLookupField) {
                            fieldConfig.type = 'url';
                            fieldConfig.fieldName = `${field}_url`;
                            fieldConfig.sortFieldName = field;
                            fieldConfig.typeAttributes = {
                                label: { fieldName: field },
                                target: '_self'
                            };
                        } else if (isEmailField || isPhoneField) {
                            fieldConfig.type = 'button';
                            fieldConfig.typeAttributes = {
                                variant: 'base',
                                label: { fieldName: field },
                                name: field,
                                title: { fieldName: field },
                                disabled: false
                            };
                        } else if (isDateField) {
                            fieldConfig.type = 'date';
                            fieldConfig.typeAttributes = {
                                year: 'numeric',
                                month: '2-digit',
                                day: '2-digit'
                            };
                        }

                        return fieldConfig;
                    }),
                    
                    // Action Column
                    {
                        type: 'action',
                        typeAttributes: { rowActions: actions },
                        fixedWidth: FIXED_WIDTH.action,
                        initialWidth: FIXED_WIDTH.action
                    }
                ];

                // Update CSS classes for table container
                const tableContainer = this.template.querySelector('.table-container');
                if (tableContainer) {
                    if (columnCount <= 5) {
                        tableContainer.classList.add('light-columns');
                        tableContainer.classList.remove('heavy-columns');
                    } else {
                        tableContainer.classList.remove('light-columns');
                        tableContainer.classList.add('heavy-columns');
                    }
                }
            }

        

                // Add the column resize handler
        handleColumnResize(event) {
            const columnName = event.detail.columnName;
            const newWidth = event.detail.width;
            
            // Store the new width in our tracking object
            this.columnWidths[columnName] = newWidth;
            
            // Update the column definition
            this.columns = this.columns.map(column => {
                if (column.fieldName === columnName) {
                    return { ...column, initialWidth: newWidth };
                }
                return column;
            });
        }

             // Add settings menu handlers
             handleSettingsClick(event) {
                console.log('Settings clicked', {
                    currentState: this.showSettingsMenu,
                    event: event
                });
                event.stopPropagation();
                this.showSettingsMenu = !this.showSettingsMenu;
                console.log('New state:', this.showSettingsMenu);
            }

        // Method to handle resetting column widths
        handleResetColumnWidths(event) {
            if (event) {
                event.preventDefault();
                event.stopPropagation();
            }
            
            // Reset column widths storage
            this.columnWidths = {};
            
            // Calculate column width based on count
            const columnCount = this.fieldsArray.length;
            const totalFixedWidth = FIXED_WIDTH.number + FIXED_WIDTH.action;
            let columnWidth;
            
            // For 5 or fewer columns, calculate based on container width
            // For more than 5 columns, use fixed width
            if (columnCount <= 5) {
                const container = this.template.querySelector('.table-container');
                const availableWidth = container ? container.offsetWidth : 1200;
                columnWidth = Math.floor((availableWidth - totalFixedWidth) / columnCount);
            } else {
                columnWidth = 255; // Fixed width for many columns
            }
            
            // Reset columns with calculated width
            this.columns = this.columns.map(column => {
                if (column.fieldName === 'rowNumber') {
                    return { ...column, initialWidth: FIXED_WIDTH.number };
                } else if (column.type === 'action') {
                    return { ...column, initialWidth: FIXED_WIDTH.action };
                } else {
                    return { ...column, initialWidth: columnWidth };
                }
            });
            
            // Get datatable component and force refresh
            const datatable = this.template.querySelector('lightning-datatable');
            if (datatable) {
                datatable.columns = [...this.columns];
            }
            
            // Close settings menu and update table responsiveness
            this.showSettingsMenu = false;
            this.updateTableResponsiveness();
            
            // Show success toast
            this.showToast('Success', 'Column widths have been reset', 'success');
        }
    
    // Add method for table responsiveness
    updateTableResponsiveness() {
        setTimeout(() => {
            const tableContainer = this.template.querySelector('.table-container');
            if (tableContainer) {
                if (this.fieldsArray.length <= 5) {
                    tableContainer.classList.add('light-columns');
                    tableContainer.classList.remove('heavy-columns');
                } else {
                    tableContainer.classList.remove('light-columns');
                    tableContainer.classList.add('heavy-columns');
                }
            }
        }, 0);
    }
    
    handleRecordSubmit(event) {
        // Prevent the default form submission
        event.preventDefault();
        
        try {
            // Show loading spinner
            this.isLoading = true;
            
            // Get the fields from the form
            const fields = event.detail.fields;
            
            // Submit the form
            this.template.querySelector('lightning-record-edit-form').submit(fields);
        } catch (error) {
            console.error('Submit Error:', error);
            this.showToast('Error', 'An error occurred while submitting the form: ' + (error.message || error.body?.message || 'Unknown error'), 'error');
        }
    }
    

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
    
        // If it's a standard action (edit, delete, etc.)
        if (action.name === 'edit' || action.name === 'delete' || action.name === 'view') {
            this.selectedRecordId = row.Id;
    
            switch (action.name) {
                case 'view':
                    this.navigateToRecord();
                    break;
                case 'edit':
                    this.showEditModal = true;
                    break;
                case 'delete':
                    this.showDeleteModal = true;
                    break;
                default:
                    break;
            }
        } 
        // If it's an email field click
        else if (row[action.name] && action.name.toLowerCase().includes('email')) {
            // Open email client
            window.location.href = `mailto:${row[action.name]}`;
        }
    }

    navigateToRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.selectedRecordId,
                objectApiName: this.childObjectApiName,
                actionName: 'view'
            }
        });
    }

    handleCloseEditModal() {
        const modal = this.template.querySelector('section[data-id="editModal"]');
        if (modal) {
            modal.classList.add('slds-fade-in-close');
            setTimeout(() => {
                this.showEditModal = false;
            }, 100);
        }
    }

    handleCloseDeleteModal() {
        this.showDeleteModal = false;
        this.selectedRecordId = null;
    }

    handleRecordSuccess(event) {
        try {
            this.isLoading = false;
            this.showEditModal = false;
            this.selectedRecordId = null;
            this.showToast('Success', 'Record updated successfully', 'success');
            this.handleRefresh();
        } catch (error) {
            console.error('Success Handler Error:', error);
            this.showToast('Error', 'An error occurred after record update: ' + (error.message || 'Unknown error'), 'error');
        }
    }

    handleRecordError(event) {
        this.isLoading = false;
        console.error('Record Error:', event.detail);
        
        let errorMessage = 'An error occurred while saving the record.';
        
        // Try to extract a more specific error message
        if (event.detail.message) {
            errorMessage = event.detail.message;
        } else if (event.detail.output && event.detail.output.fieldErrors) {
            // Handle field-specific errors
            const fieldErrors = event.detail.output.fieldErrors;
            const firstFieldError = Object.values(fieldErrors)[0];
            if (firstFieldError && firstFieldError[0]) {
                errorMessage = firstFieldError[0].message;
            }
        } else if (event.detail.detail) {
            errorMessage = event.detail.detail;
        }
        
        this.showToast('Error', errorMessage, 'error');
    }

    handleConfirmDelete() {
        console.log('Deleting record with ID:', this.selectedRecordId);
        console.log('Object Name:', this.childObjectApiName);
    
        this.isLoading = true; // Show spinner during deletion
        deleteRecord({ 
            recordId: this.selectedRecordId, 
            objectName: this.childObjectApiName 
        })
            .then(() => {
                console.log('Record deleted successfully');
                this.showToast('Success', 'Record deleted successfully', 'success');
                this.showDeleteModal = false; // Close modal
                this.selectedRecordId = null; // Clear selected record
                this.handleRefresh(); // Refresh the datatable
            })
            .catch(error => {
                console.error('Error deleting record:', error);
                this.showToast('Error', error.body?.message || 'Failed to delete record.', 'error');
                this.showDeleteModal = false; // Ensure modal closes even if delete fails
            })
            .finally(() => {
                this.isLoading = false; // Stop spinner
            });
    }
    


    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        console.log('Sort triggered:', { sortedBy, sortDirection });
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
    
        let clonedData = [...this.filteredData];
        
        clonedData.sort((a, b) => {
            let valueA, valueB;
            
            // Handle relationship fields
            if (sortedBy.includes('_url')) {
                // Remove _url suffix to get the base field name
                const baseField = sortedBy.replace('_url', '');
                if (baseField.includes('.')) {
                    const [relationshipField, field] = baseField.split('.');
                    valueA = a[relationshipField] ? a[relationshipField][field] : '';
                    valueB = b[relationshipField] ? b[relationshipField][field] : '';
                }
            } else if (sortedBy.includes('.')) {
                const [relationshipField, field] = sortedBy.split('.');
                valueA = a[relationshipField] ? a[relationshipField][field] : '';
                valueB = b[relationshipField] ? b[relationshipField][field] : '';
            } else {
                valueA = sortedBy === 'nameUrl' ? a.Name : a[sortedBy];
                valueB = sortedBy === 'nameUrl' ? b.Name : b[sortedBy];
            }
            
            // Handle null or empty values
            if (!valueA && valueA !== 0) return 1;
            if (!valueB && valueB !== 0) return -1;
            if (valueA === valueB) return 0;
            
            // String comparison
            if (typeof valueA === 'string') {
                valueA = valueA.toLowerCase();
                valueB = valueB.toLowerCase();
            }
            
            // Simple comparison
            return sortDirection === 'asc' 
                ? (valueA > valueB ? 1 : -1)
                : (valueA > valueB ? -1 : 1);
        });
    
        // Always reassign row numbers after sorting
        const startingNumber = (this.pageNumber - 1) * this.recordsPerPage + 1;
        this.filteredData = clonedData.map((record, index) => ({
            ...record,
            rowNumber: startingNumber + index
        }));
    }


    getSortValue(record, field) {
        const column = this.columns.find(col => col.fieldName === field);
        // Use sortFieldName if specified, otherwise use fieldName
        const sortField = column?.sortFieldName || field;
        
        // For lookup fields that use _url suffix
        if (sortField.endsWith('_url')) {
            const baseField = sortField.replace('_url', '');
            return record[baseField] || '';
        }
        
        return record[sortField] || '';
    }

    // Update the wire service to include search parameters
    @wire(getRecords, {
        childObject: '$childObjectApiName',
        parentLookupField: '$parentLookupField',
        parentId: '$recordId',
        fields: '$fieldsArray',
        pageSize: '$recordsPerPage',
        pageNumber: '$pageNumber',
        searchTerm: '$debouncedSearchTerm',
        searchableFields: '$searchableFieldsArray'
    })
    wiredRecords(result) {
        this.wiredRecordResult = result;
        this.isLoading = true;
        
        if (result.data) {
            console.log('Received data:', {
                totalRecords: result.data.totalRecords,
                currentPage: this.pageNumber,
                searchTerm: this.debouncedSearchTerm
            });
            
            this.processRecords(result.data);
            this.error = undefined;
        } else if (result.error) {
            this.handleError(result.error);
        }
        
        this.isLoading = false;
    }

    handleError(error) {
        this.error = error;
        this.data = [];
        this.filteredData = [];
        
        if (error) {
            let errorMessage = 'Unknown error';
            if (Array.isArray(error.body)) {
                errorMessage = error.body.map(e => e.message).join(', ');
            } else if (error.body && typeof error.body.message === 'string') {
                errorMessage = error.body.message;
            }
            
            // Display error toast
            this.showToast('Error', errorMessage, 'error');
            
            // Log error for debugging
            console.error('Error in wired records:', {
                error: error,
                message: errorMessage
            });
        }
        
        this.isLoading = false;
    }

    
    processRecords(data) {
        console.log('--- processRecords START ---');
        if (!data || !data.records) {
            console.log('No data or records found');
            this.data = [];
            return;
        }
    
        const startingNumber = (this.pageNumber - 1) * this.recordsPerPage + 1;
        console.log('Starting Number:', startingNumber);
        
        this.data = data.records.map((record, index) => {
            const flatRecord = { ...record };
            // ONLY THIS LINE FOR ROW NUMBER
            flatRecord.rowNumber = startingNumber + index;
            
            console.log(`Processing Record: ${record.Name} - Row Number: ${flatRecord.rowNumber}`);
            
            // Handle Name field
            if (flatRecord.Name) {
                flatRecord.nameUrl = `/${flatRecord.Id}`;
            }
    
            // Process all fields
            this.fieldsArray.forEach(field => {
                if (field.includes('.')) {
                    // Handle relationship fields
                    const [relationshipField, relatedField] = field.split('.');
                    if (flatRecord[relationshipField]) {
                        flatRecord[`${field}`] = flatRecord[relationshipField][relatedField];
                        flatRecord[`${field}_url`] = `/${flatRecord[relationshipField].Id}`;
                        flatRecord[`${field}_label`] = flatRecord[relationshipField][relatedField];
                    }
                } else {
                    // Handle email fields
                    if (field.toLowerCase().includes('email') && flatRecord[field]) {
                        flatRecord[`${field}_url`] = `mailto:${flatRecord[field]}`;
                    }
                    
                    // Handle phone fields
                    if (field.toLowerCase().includes('phone') && flatRecord[field]) {
                        const cleanNumber = flatRecord[field].replace(/\D/g, '');
                        flatRecord[`${field}_formatted`] = this.formatPhoneNumber(flatRecord[field]);
                        flatRecord[`${field}_url`] = `tel:${cleanNumber}`;
                    }
                }
            });
    
            return flatRecord;
        });
    
        console.log('Processed Records:', JSON.stringify(this.data.map(record => ({
            id: record.Id,
            name: record.Name,
            rowNumber: record.rowNumber
        }))));
    
        this.filteredData = [...this.data];
        this.totalPages = Math.ceil(data.totalRecords / this.recordsPerPage);
        console.log('--- processRecords END ---');
    }
    

    formatPhoneNumber(phoneNumber) {
        const cleaned = phoneNumber.replace(/\D/g, '');
        if (cleaned.length === 10) {
            return `(${cleaned.slice(0,3)}) ${cleaned.slice(3,6)}-${cleaned.slice(6)}`;
        }
        return phoneNumber;
    }
        // Update connectedCallback to handle click outside
        connectedCallback() {
            // Initialize columns
            this.initializeColumns();
            
            // Add debounced resize handler
            this.handleResize = this.debounce(() => {
                this.initializeColumns();
                this.updateTableResponsiveness();
            }, 250);
            
            window.addEventListener('resize', this.handleResize);
            
            // Add click outside listener for settings menu
            this.handleClickOutside = (event) => {
                const settingsMenu = this.template.querySelector('.settings-dropdown');
                const settingsButton = this.template.querySelector('.settings-button');
                
                if (this.showSettingsMenu && 
                    settingsMenu && 
                    settingsButton && 
                    !settingsMenu.contains(event.target) && 
                    !settingsButton.contains(event.target)) {
                    this.showSettingsMenu = false;
                }
            };
            
            document.addEventListener('click', this.handleClickOutside);
            
            // Initial table responsiveness update
            this.updateTableResponsiveness();
        }
        
        // Add debounce utility method
        debounce(fn, delay) {
            let timeoutId;
            return (...args) => {
                if (timeoutId) {
                    clearTimeout(timeoutId);
                }
                timeoutId = setTimeout(() => {
                    fn(...args);
                }, delay);
            };
        }

        disconnectedCallback() {
            // Remove window resize listener
            if (this.handleResize) {
                window.removeEventListener('resize', this.handleResize);
            }
            
            // Remove document click listener
            if (this.handleClickOutside) {
                document.removeEventListener('click', this.handleClickOutside);
            }
        }


        // Update getColumnLabel method
        getColumnLabel(fieldApi, index) {
            if (this.columnLabelsArray[index]) {
                return this.columnLabelsArray[index];
            }
            if (this.objectInfo) {
                const fieldInfo = this.objectInfo.fields[fieldApi];
                if (fieldInfo) {
                    return fieldInfo.label;
                }
            }
            return this.formatLabel(fieldApi);
        }

    // Update handleSearch to reset pagination
    handleSearch(event) {
        this.searchTerm = event.target.value;
        
        // Clear any existing timeout
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }
        
        // Set a new timeout
        this.searchTimeout = setTimeout(() => {
            this.debouncedSearchTerm = this.searchTerm;
            this.pageNumber = 1; // Reset to first page only when searching
        }, 300);
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

   // Update handleNewRecord method
   handleNewRecord() {
    const defaultValues = encodeDefaultFieldValues({
        [this.parentLookupField]: this.recordId
    });

    this[NavigationMixin.Navigate]({
        type: 'standard__objectPage',
        attributes: {
            objectApiName: this.childObjectApiName,
            actionName: 'new'
        },
        state: {
            defaultFieldValues: defaultValues
        }
    });
}

    // Modify the handleFlowLaunch method
    handleFlowLaunch() {
        if (!this.hasFlowName) {
            this.showToast('Error', 'No flow specified', 'error');
            return;
        }
        
        // Set up flow input variables with current context
        this.flowInputVariables = [
            {
                name: 'recordId',
                type: 'String',
                value: this.recordId
            }
            // Add any other variables your flow needs
        ];
        
        this.flowKey = Date.now();
        this.showFlowModal = true;
    }

    handleFlowStatusChange(event) {
        if (event.detail.status === 'FINISHED') {
            // Wait a brief moment before closing to ensure flow completes
            setTimeout(() => {
                this.handleCloseModal();
                this.handleRefresh();
                this.showToast('Success', 'Flow completed successfully', 'success');
            }, 100);
        } else if (event.detail.status === 'ERROR') {
            this.showToast('Error', event.detail.message || 'An error occurred while running the flow', 'error');
            this.handleCloseModal();
        }
    }

    handleCloseModal() {
        // Force cleanup of the current flow instance
        const flowComponent = this.template.querySelector('lightning-flow');
        if (flowComponent) {
            try {
                flowComponent.pause();
                flowComponent.stop();
            } catch (error) {
                console.error('Error stopping flow:', error);
            }
        }
        
        // Reset all modal-related states
        this.showFlowModal = false;
        this.flowKey = null;
        this.flowInputVariables = [];
        
        // Force component refresh
        this.handleRefresh();
    }

        // Add click handler for the backdrop
    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseModal();
        }
    }
    
    handlePrevious() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.refresh();
        }
    }

    handleNext() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.refresh();
        }
    }

    formatLabel(fieldName) {
        return fieldName
            .split(/(?=[A-Z])|_/)
            .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
            .join(' ')
            .replace(/\s+[cC]$/, '')
            .replace(/__c$/i, '');
    }

    get isFirstPage() {
        return this.pageNumber === 1;
    }

    get isLastPage() {
        return this.pageNumber === this.totalPages;
    }

    // Add getter for totalPages calculation
    get totalPages() {
        if (this.wiredRecordResult?.data?.totalRecords) {
            return Math.ceil(this.wiredRecordResult.data.totalRecords / this.recordsPerPage);
        }
        return 0;
    }

    // Update refresh method
    @api
    refresh() {
        // Don't reset search term or page number here
        return refreshApex(this.wiredRecordResult);
    }

    handleRefresh() {
        console.log('Refreshing datatable...');
        this.isLoading = true; // Show spinner
        refreshApex(this.wiredRecordResult)
            .then(() => {
                console.log('Data refreshed successfully');
            })
            .catch(error => {
                console.error('Error refreshing data:', error);
            })
            .finally(() => {
                this.isLoading = false; // Hide spinner
            });
    }
    
    

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}