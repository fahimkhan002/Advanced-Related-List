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
   
    // get hasFlowTitle() {
    //     return this.flowTitle;
    // }

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

    initializeColumns() {
        const columnCount = this.fieldsArray.length;
        let columnWidth;

        if (columnCount <= 5) {
            const totalFixedWidth = FIXED_WIDTH.number + FIXED_WIDTH.action;
            columnWidth = `calc((100% - ${totalFixedWidth}px) / ${columnCount})`;
        } else {
            columnWidth = 255;
        }

        this.columns = [
            {
                label: '#',
                fieldName: 'rowNumber',
                type: 'number',
                sortable: false,
                fixedWidth: FIXED_WIDTH.number
            },
            ...this.fieldsArray.map((field, index) => {
                const isNameField = field.toLowerCase() === 'name';
                const isLookupField = field.includes('.');

                let fieldConfig = {
                    label: this.getColumnLabel(field, index),
                    fieldName: isNameField ? 'nameUrl' : isLookupField ? `${field}_url` : field,
                    sortable: true,
                    wrapText: false,
                    initialWidth: columnWidth
                };

                if (isNameField || isLookupField) {
                    fieldConfig.type = 'url';
                    fieldConfig.typeAttributes = {
                        label: { 
                            fieldName: isLookupField ? field : 'Name'
                        },
                        target: '_self'
                    };
                }

                return fieldConfig;
            }),
            {
                type: 'action',
                typeAttributes: { rowActions: actions },
                fixedWidth: FIXED_WIDTH.action
            }
        ];

        this.updateTableResponsiveness();
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
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
    
        let clonedData = [...this.filteredData];
        
        // Store the original row numbers before sorting
        const rowNumbers = clonedData.map(item => item.rowNumber);
        
        clonedData.sort((a, b) => {
            let valueA = a[sortedBy] || '';
            let valueB = b[sortedBy] || '';
    
            // Handle different data types
            if (typeof valueA === 'string') {
                valueA = valueA.toLowerCase();
                valueB = valueB.toLowerCase();
            } else if (valueA instanceof Date) {
                valueA = valueA.getTime();
                valueB = valueB.getTime();
            }
    
            let result = valueA > valueB ? 1 : -1;
            return sortDirection === 'asc' ? result : -result;
        });
    
        // Restore the original row numbers after sorting
        clonedData = clonedData.map((record, index) => ({
            ...record,
            rowNumber: rowNumbers[index]
        }));
    
        this.filteredData = clonedData;
    }

    @wire(getRecords, {
        childObject: '$childObjectApiName',
        parentLookupField: '$parentLookupField',
        parentId: '$recordId',
        fields: '$fieldsArray',
        pageSize: '$recordsPerPage',
        pageNumber: '$pageNumber'
    })
    wiredRecords(result) {
        this.wiredRecordResult = result;
        this.isLoading = true;
        
        if (result.data) {

            console.log('Received Data:', JSON.stringify(result.data));

            this.processRecords(result.data);
            this.error = undefined;
        } else if (result.error) {
            console.log('Error in wire:', result.error);
            this.handleError(result.error);
        }
        
        this.isLoading = false;
    }

    
    processRecords(data) {

        console.log('Processing Records:', JSON.stringify(data));

        if (!data || !data.records) {
            console.log('No data or records found');
            this.data = [];
            return;
        }

        const startingNumber = (this.pageNumber - 1) * this.recordsPerPage + 1;
        
        this.data = data.records.map((record, index) => {
            const flatRecord = { ...record };
            flatRecord.rowNumber = startingNumber + index;

            // Handle Name field
            if (flatRecord.Name) {
                flatRecord.nameUrl = `/${flatRecord.Id}`;
            }

            // Handle relationship fields
            this.fieldsArray.forEach(field => {
                if (field.includes('.')) {
                    const [relationshipField, relatedField] = field.split('.');
                    if (flatRecord[relationshipField]) {
                        flatRecord[`${field}`] = flatRecord[relationshipField][relatedField];
                        flatRecord[`${field}_url`] = `/${flatRecord[relationshipField].Id}`;
                        flatRecord[`${field}_label`] = flatRecord[relationshipField][relatedField];
                    }
                }
            });

            console.log('Processed Record:', JSON.stringify(flatRecord));

            return flatRecord;
        });

        this.filteredData = [...this.data];
        this.totalPages = Math.ceil(data.totalRecords / this.recordsPerPage);
    }
    

        connectedCallback() {
            this.initializeColumns();
            // Add event listener for window resize
            this.handleResize = () => this.updateTableResponsiveness();
            window.addEventListener('resize', this.handleResize);

        }

        disconnectedCallback() {
            window.removeEventListener('resize', this.handleResize);

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

            handleSearch(event) {
                const searchTerm = event.target.value.toLowerCase();

                if (searchTerm) {
                    this.filteredData = this.data.filter(record => {
                        return this.searchableFieldsArray.some(field => {
                            const fieldValue = record[field];
                            return fieldValue && String(fieldValue).toLowerCase().includes(searchTerm);
                        });
                    });
                } else {
                    this.filteredData = [...this.data];
                }
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

    @api
    refresh() {
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