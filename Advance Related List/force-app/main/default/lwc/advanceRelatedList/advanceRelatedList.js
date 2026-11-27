import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { deleteRecord } from 'lightning/uiRecordApi';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import FORM_FACTOR from '@salesforce/client/formFactor';
import LOCALE from '@salesforce/i18n/locale';
import getRows from '@salesforce/apex/RelatedListController.getRows';
import deleteRows from '@salesforce/apex/RelatedListController.deleteRows';
import EditModal from 'c/arlEditModal';
import FlowModal from 'c/arlFlowModal';
import { clampPageSize, describeFilter, reduceError, safeHexColor } from 'c/arlUtils';

const SEARCH_DELAY_MS = 300;
const STATUS_OK = 'OK';
const STATUS_STALE = 'STALE_CURSOR';
const DEFAULT_ICON = 'standard:related_list';

const ROW_ACTIONS = {
    view: { label: 'View', name: 'view' },
    edit: { label: 'Edit', name: 'edit' },
    delete: { label: 'Delete', name: 'delete' }
};

/**
 * Advanced Related List.
 *
 * Data comes only from RelatedListController.getRows, which re-validates the list definition (or
 * the legacy App Builder properties) for the running user on every request. The browser never
 * decides which records, fields or actions are allowed; hidden buttons are a convenience only.
 */
export default class AdvanceRelatedList extends NavigationMixin(LightningElement) {
    // ===== PUBLIC PROPERTIES (names unchanged from v1) =====
    @api childObjectApiName;
    @api parentObjectApiName; // kept for page compatibility; not used
    @api parentLookupField;
    @api fieldsToDisplay = '';
    @api columnLabels = '';
    @api searchableFields = '';
    @api sortableFields = '';
    @api recordsPerPage = 10;
    @api flowName;
    @api flowTitle = 'Run Flow';
    @api listTitle;
    @api customIconName;
    @api iconBackgroundColor;

    _recordId;
    _listDefinition;

    /** Parent record id (set by the record page). Changing it resets the list. */
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && this._connected) {
            this.resetAndLoad();
        }
    }

    /** DeveloperName of an Advanced Related List definition (Custom Metadata). */
    @api
    get listDefinition() {
        return this._listDefinition;
    }
    set listDefinition(value) {
        const changed = value !== this._listDefinition;
        this._listDefinition = value;
        if (changed && this._connected) {
            this.resetAndLoad();
        }
    }

    // ===== STATE =====
    _connected = false;
    isLoading = false;
    hasLoaded = false;
    status;
    message;
    context;
    columnInfo = [];
    rows = [];
    totalCount;
    totalCountCapped = false;
    hasMore = false;
    cursors = [null];
    pageIndex = 0;

    searchInput = '';
    appliedSearch = '';
    filters = [];
    filterLogic = 'AND';
    showFilters = false;
    sortKey;
    sortDirection;
    userSorted = false;

    selectedIds = [];
    columnWidths = {};
    rowErrors = [];
    announcement = '';

    requestSeq = 0;
    searchTimer;
    staleRetry = false;

    isSmall = FORM_FACTOR === 'Small';

    // ===== LIFECYCLE =====

    connectedCallback() {
        this._connected = true;
        this.load();
    }

    disconnectedCallback() {
        this._connected = false;
        clearTimeout(this.searchTimer);
        this.requestSeq++; // ignore responses that arrive after removal
    }

    // ===== PUBLIC API =====

    /**
     * Reloads the list from the first page (fresh total). Unchanged public method name.
     * @returns {Promise<void>}
     */
    @api
    refresh() {
        this.pageIndex = 0;
        this.cursors = [null];
        return this.load();
    }

    // ===== DATA LOADING =====

    get pageSize() {
        return clampPageSize(this.recordsPerPage);
    }

    buildRequest() {
        const usesDefinition = Boolean(this._listDefinition && String(this._listDefinition).trim());
        return {
            definitionKey: usesDefinition ? String(this._listDefinition).trim() : null,
            parentId: this._recordId || null,
            legacy: usesDefinition
                ? null
                : {
                      childObjectApiName: this.childObjectApiName,
                      parentLookupField: this.parentLookupField,
                      fieldsToDisplay: this.fieldsToDisplay,
                      searchableFields: this.searchableFields,
                      sortableFields: this.sortableFields,
                      columnLabels: this.columnLabels,
                      flowName: this.flowName
                  },
            searchTerm: this.appliedSearch || null,
            filters: this.filters.map((f) => ({ columnKey: f.columnKey, operator: f.operator, value: f.value })),
            filterLogic: this.filterLogic,
            sortKey: this.userSorted ? this.sortKey : null,
            sortDirection: this.userSorted ? this.sortDirection : null,
            pageSize: this.pageSize,
            cursor: this.cursors[this.pageIndex] || null
        };
    }

    async load() {
        const seq = ++this.requestSeq;
        this.isLoading = true;
        try {
            const response = await getRows({ request: this.buildRequest() });
            if (seq !== this.requestSeq) {
                return; // a newer request superseded this one
            }
            if (response && response.status === STATUS_STALE && !this.staleRetry) {
                this.staleRetry = true;
                this.pageIndex = 0;
                this.cursors = [null];
                this.clearSelection();
                await this.load();
                return;
            }
            this.staleRetry = false;
            this.applyResponse(response);
        } catch (error) {
            if (seq !== this.requestSeq) {
                return;
            }
            this.status = 'ERROR';
            this.message = reduceError(error);
            this.rows = [];
        } finally {
            if (seq === this.requestSeq) {
                this.isLoading = false;
                this.hasLoaded = true;
            }
        }
    }

    applyResponse(response) {
        this.status = response ? response.status : 'ERROR';
        this.message = response ? response.message : 'Something went wrong. Try again.';
        if (this.status !== STATUS_OK) {
            this.rows = [];
            this.columnInfo = [];
            this.context = undefined;
            this.totalCount = undefined;
            this.hasMore = false;
            this.clearSelection();
            this.announce(this.message);
            return;
        }
        this.context = response.context;
        this.columnInfo = response.columns || [];
        if (!this.userSorted) {
            this.sortKey = response.context.sortKey;
            this.sortDirection = response.context.sortDirection;
        }
        if (response.totalCount !== undefined && response.totalCount !== null) {
            this.totalCount = response.totalCount;
            this.totalCountCapped = Boolean(response.totalCountCapped);
        }
        this.hasMore = Boolean(response.hasMore);
        const cursors = this.cursors.slice(0, this.pageIndex + 1);
        if (response.nextCursor) {
            cursors[this.pageIndex + 1] = response.nextCursor;
        }
        this.cursors = cursors;
        this.rows = (response.rows || []).map((row) => this.toDisplayRow(row));
        const present = new Set(this.rows.map((r) => r.id));
        this.selectedIds = this.selectedIds.filter((id) => present.has(id));
        this.announce(this.rangeText);
    }

    toDisplayRow(row) {
        const display = { ...row };
        this.columnInfo.forEach((col) => {
            const linkId = row[`${col.key}__id`];
            if (linkId) {
                display[`${col.key}__url`] = `/lightning/r/${linkId}/view`;
            }
            if (col.type === 'percent' && typeof row[col.key] === 'number') {
                display[col.key] = row[col.key] / 100;
            }
        });
        return display;
    }

    resetAndLoad() {
        this.pageIndex = 0;
        this.cursors = [null];
        this.totalCount = undefined;
        this.rowErrors = [];
        this.clearSelection();
        this.load();
    }

    // ===== GETTERS: HEADER =====

    get iconName() {
        return this.customIconName || DEFAULT_ICON;
    }

    get iconStyle() {
        const color = safeHexColor(this.iconBackgroundColor);
        return color ? `background-color: ${color}; border-radius: 0.25rem;` : '';
    }

    get objectLabelPlural() {
        return (this.context && this.context.objectLabelPlural) || 'Records';
    }

    get title() {
        return this.listTitle || this.objectLabelPlural;
    }

    get countLabel() {
        if (this.totalCount === undefined || this.totalCount === null) {
            return '';
        }
        const formatted = new Intl.NumberFormat(LOCALE).format(this.totalCount);
        return this.totalCountCapped ? `(${formatted}+)` : `(${formatted})`;
    }

    get searchLabel() {
        return `Search ${this.objectLabelPlural}`;
    }

    get hasSearchableColumns() {
        return this.columnInfo.some((c) => c.searchable);
    }

    get filterableColumns() {
        return this.columnInfo.filter((c) => c.filterable);
    }

    get hasFilterableColumns() {
        return this.filterableColumns.length > 0;
    }

    get filterButtonVariant() {
        return this.filters.length ? 'border-filled' : 'border';
    }

    get filterButtonLabel() {
        return this.filters.length ? `Filters (${this.filters.length} active)` : 'Filters';
    }

    get canCreate() {
        return Boolean(this.context && this.context.canCreate);
    }

    get canBulkDelete() {
        return Boolean(this.context && this.context.canBulkDelete) && !this.isSmall;
    }

    get hasFlow() {
        return Boolean(this.context && this.context.flowApiName);
    }

    get bulkDeleteLabel() {
        return `Delete selected (${this.selectedIds.length})`;
    }

    get bulkDeleteDisabled() {
        return this.selectedIds.length === 0 || this.isLoading;
    }

    get maxRowSelection() {
        const max = (this.context && this.context.maxDeleteBatch) || 100;
        return Math.min(max, this.pageSize);
    }

    get showSettingsMenu() {
        return !this.isSmall;
    }

    get ariaBusy() {
        return this.isLoading ? 'true' : 'false';
    }

    // ===== GETTERS: STATES =====

    get isOk() {
        return this.status === STATUS_OK;
    }

    get isConfigError() {
        return this.status === 'CONFIG_ERROR';
    }

    get isAccessError() {
        return this.status === 'ACCESS_ERROR';
    }

    get isInputError() {
        return this.status === 'INPUT_ERROR';
    }

    get isGenericError() {
        return this.status === 'ERROR';
    }

    get showInitialSpinner() {
        return this.isLoading && !this.hasLoaded;
    }

    get hasRows() {
        return this.isOk && this.rows.length > 0;
    }

    get hasCriteria() {
        return Boolean(this.appliedSearch) || this.filters.length > 0;
    }

    get isEmpty() {
        return this.isOk && this.rows.length === 0 && !this.hasCriteria;
    }

    get isNoMatch() {
        return this.isOk && this.rows.length === 0 && this.hasCriteria;
    }

    get emptyText() {
        return `No ${this.objectLabelPlural.toLowerCase()} yet.`;
    }

    get hasOmittedColumns() {
        return Boolean(this.context && this.context.omittedColumnCount > 0);
    }

    get activeFilterPills() {
        return this.filters.map((f, index) => ({ key: `${f.columnKey}-${index}`, index, label: describeFilter(f, this.columnInfo) }));
    }

    get hasActiveFilters() {
        return this.filters.length > 0;
    }

    get logicText() {
        return this.filterLogic === 'OR' ? 'Matching any condition' : 'Matching all conditions';
    }

    get hasRowErrors() {
        return this.rowErrors.length > 0;
    }

    // ===== GETTERS: TABLE =====

    get datatableColumns() {
        const actions = this.rowActions;
        const cols = this.columnInfo.filter((c) => c.visible).map((c) => this.toDatatableColumn(c));
        if (actions.length) {
            cols.push({ type: 'action', typeAttributes: { rowActions: actions, menuAlignment: 'auto' } });
        }
        return cols;
    }

    toDatatableColumn(col) {
        const base = {
            label: col.label,
            fieldName: col.key,
            sortable: Boolean(col.sortable),
            wrapText: true,
            hideDefaultActions: true
        };
        if (this.columnWidths[col.key]) {
            base.initialWidth = this.columnWidths[col.key];
        }
        switch (col.type) {
            case 'name':
            case 'link':
                return {
                    ...base,
                    type: 'url',
                    fieldName: `${col.key}__url`,
                    typeAttributes: { label: { fieldName: col.key }, target: '_self', tooltip: { fieldName: col.key } }
                };
            case 'email':
            case 'phone':
            case 'url':
            case 'boolean':
                return { ...base, type: col.type };
            case 'number':
                return { ...base, type: 'number', typeAttributes: { maximumFractionDigits: col.scale || 0 }, cellAttributes: { alignment: 'right' } };
            case 'currency':
                return {
                    ...base,
                    type: 'currency',
                    typeAttributes: { currencyCode: { fieldName: `${col.key}__cur` }, currencyDisplayAs: 'symbol' },
                    cellAttributes: { alignment: 'right' }
                };
            case 'percent':
                return { ...base, type: 'percent', typeAttributes: { maximumFractionDigits: col.scale || 0 }, cellAttributes: { alignment: 'right' } };
            case 'date':
                return { ...base, type: 'date-local', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } };
            case 'datetime':
                return {
                    ...base,
                    type: 'date',
                    typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }
                };
            default:
                return { ...base, type: 'text' };
        }
    }

    get rowActions() {
        if (!this.context) {
            return [];
        }
        const actions = [ROW_ACTIONS.view];
        if (this.context.canEdit) {
            actions.push(ROW_ACTIONS.edit);
        }
        if (this.context.canDelete) {
            actions.push(ROW_ACTIONS.delete);
        }
        return actions;
    }

    get datatableSortedBy() {
        const col = this.columnInfo.find((c) => c.key === this.sortKey && c.visible);
        if (!col) {
            return undefined;
        }
        return col.type === 'name' || col.type === 'link' ? `${col.key}__url` : col.key;
    }

    get rowNumberOffset() {
        return this.pageIndex * this.pageSize;
    }

    get hideCheckboxColumn() {
        return !this.canBulkDelete;
    }

    // ===== GETTERS: SMALL SCREEN =====

    get cards() {
        const visible = this.columnInfo.filter((c) => c.visible);
        const titleCol = visible.find((c) => c.type === 'name') || visible[0];
        const detailCols = visible.filter((c) => c !== titleCol).slice(0, 3);
        return this.rows.map((row) => ({
            id: row.id,
            title: titleCol && row[titleCol.key] !== undefined ? String(row[titleCol.key]) : row.id,
            menuLabel: `Actions for ${titleCol && row[titleCol.key] !== undefined ? row[titleCol.key] : 'record'}`,
            details: detailCols.map((c) => ({ key: c.key, label: c.label, value: this.plainText(c, row[c.key]) }))
        }));
    }

    plainText(col, value) {
        if (value === undefined || value === null) {
            return '';
        }
        if (col.type === 'boolean') {
            return value ? 'Yes' : 'No';
        }
        if (col.type === 'currency' || col.type === 'number' || col.type === 'percent') {
            return new Intl.NumberFormat(LOCALE).format(value);
        }
        return String(value);
    }

    get sortOptions() {
        return this.columnInfo.filter((c) => c.sortable && c.visible).map((c) => ({ label: c.label, value: c.key }));
    }

    get hasSortOptions() {
        return this.sortOptions.length > 0;
    }

    get directionOptions() {
        return [
            { label: 'Ascending', value: 'asc' },
            { label: 'Descending', value: 'desc' }
        ];
    }

    // ===== GETTERS: PAGINATION =====

    get isFirstPage() {
        return this.pageIndex === 0 || this.isLoading;
    }

    get isLastPage() {
        return !this.hasMore || this.isLoading;
    }

    get showPagination() {
        return this.isOk && (this.pageIndex > 0 || this.hasMore);
    }

    get rangeText() {
        if (!this.isOk) {
            return '';
        }
        if (this.rows.length === 0) {
            return this.hasCriteria ? 'No records match your search or filters.' : this.emptyText;
        }
        const nf = new Intl.NumberFormat(LOCALE);
        const start = this.pageIndex * this.pageSize + 1;
        const end = start + this.rows.length - 1;
        if (this.totalCount === undefined || this.totalCount === null) {
            return `Showing ${nf.format(start)}–${nf.format(end)}`;
        }
        const total = nf.format(this.totalCount) + (this.totalCountCapped ? '+' : '');
        return `Showing ${nf.format(start)}–${nf.format(end)} of ${total}`;
    }

    get pageText() {
        const page = this.pageIndex + 1;
        if (this.totalCount && !this.totalCountCapped) {
            return `Page ${page} of ${Math.max(1, Math.ceil(this.totalCount / this.pageSize))}`;
        }
        return `Page ${page}`;
    }

    // ===== HANDLERS: SEARCH / FILTER / SORT =====

    handleSearchInput(event) {
        this.searchInput = event.target.value || '';
        clearTimeout(this.searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(() => {
            const next = this.searchInput.trim();
            if (next !== this.appliedSearch) {
                this.appliedSearch = next;
                this.resetAndLoad();
            }
        }, SEARCH_DELAY_MS);
    }

    handleToggleFilters() {
        this.showFilters = !this.showFilters;
    }

    handleFilterApply(event) {
        this.filters = event.detail.filters;
        this.filterLogic = event.detail.logic === 'OR' ? 'OR' : 'AND';
        this.showFilters = false;
        this.resetAndLoad();
        this.focusFilterButton();
    }

    handleFilterCancel() {
        this.showFilters = false;
        this.focusFilterButton();
    }

    handleRemoveFilter(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.filters = this.filters.filter((_, i) => i !== index);
        this.resetAndLoad();
        this.focusFilterButton();
    }

    handleClearAll() {
        clearTimeout(this.searchTimer);
        this.filters = [];
        this.filterLogic = 'AND';
        this.appliedSearch = '';
        this.searchInput = '';
        this.showFilters = false;
        this.resetAndLoad();
        const search = this.template.querySelector('[data-id="search"]');
        if (search) {
            search.value = '';
            search.focus();
        }
    }

    handleSort(event) {
        const fieldName = event.detail.fieldName;
        const col = this.columnInfo.find((c) => c.key === fieldName || `${c.key}__url` === fieldName);
        if (!col) {
            return;
        }
        this.applySort(col.key, event.detail.sortDirection);
    }

    handleSmallSortField(event) {
        this.applySort(event.detail.value, this.sortDirection || 'asc');
    }

    handleSmallSortDirection(event) {
        if (this.sortKey) {
            this.applySort(this.sortKey, event.detail.value);
        }
    }

    applySort(key, direction) {
        this.sortKey = key;
        this.sortDirection = direction === 'desc' ? 'desc' : 'asc';
        this.userSorted = true;
        this.resetAndLoad();
    }

    // ===== HANDLERS: PAGINATION / SELECTION =====

    handlePrevious() {
        if (this.pageIndex > 0) {
            this.pageIndex -= 1;
            this.clearSelection();
            this.load();
        }
    }

    handleNext() {
        if (this.hasMore && this.cursors[this.pageIndex + 1]) {
            this.pageIndex += 1;
            this.clearSelection();
            this.load();
        }
    }

    handleRowSelection(event) {
        this.selectedIds = (event.detail.selectedRows || []).map((row) => row.id);
    }

    clearSelection() {
        this.selectedIds = [];
    }

    handleColumnResize(event) {
        const widths = { ...this.columnWidths };
        const columns = event.detail.columnWidths || [];
        this.datatableColumns.forEach((col, index) => {
            if (col.type !== 'action' && columns[index]) {
                const key = col.fieldName.replace(/__url$/, '');
                widths[key] = columns[index];
            }
        });
        this.columnWidths = widths;
    }

    handleSettingsSelect(event) {
        if (event.detail.value === 'resetWidths') {
            this.columnWidths = {};
            this.announce('Column widths reset.');
        }
    }

    // ===== HANDLERS: ACTIONS =====

    handleRefresh() {
        this.rowErrors = [];
        this.refresh();
    }

    handleRetry() {
        this.resetAndLoad();
    }

    handleNew() {
        const ctx = this.context;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: ctx.objectApiName, actionName: 'new' },
            state: {
                defaultFieldValues: encodeDefaultFieldValues({ [ctx.lookupField]: this._recordId }),
                navigationLocation: 'RELATED_LIST'
            }
        });
    }

    handleRowAction(event) {
        this.runRowAction(event.detail.action.name, event.detail.row.id);
    }

    handleCardAction(event) {
        this.runRowAction(event.detail.value, event.currentTarget.dataset.id);
    }

    handleCardOpen(event) {
        event.preventDefault();
        this.runRowAction('view', event.currentTarget.dataset.id);
    }

    runRowAction(action, recordId) {
        if (action === 'view') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId, objectApiName: this.context.objectApiName, actionName: 'view' }
            });
        } else if (action === 'edit') {
            this.editRecord(recordId);
        } else if (action === 'delete') {
            this.deleteOne(recordId);
        }
    }

    async editRecord(recordId) {
        const result = await EditModal.open({
            size: 'medium',
            label: `Edit ${this.context.objectLabel}`,
            heading: `Edit ${this.context.objectLabel}`,
            recordId,
            objectApiName: this.context.objectApiName,
            fields: this.context.editFields
        });
        if (result === 'saved') {
            this.toast('Saved', `The ${this.context.objectLabel.toLowerCase()} was saved.`, 'success');
            await this.load();
            this.restoreFocus();
        }
    }

    async deleteOne(recordId) {
        const label = this.context.objectLabel;
        const confirmed = await LightningConfirm.open({
            label: `Delete ${label}`,
            message: `Delete this ${label.toLowerCase()}? You can't undo this.`,
            theme: 'error',
            variant: 'header'
        });
        if (!confirmed) {
            return;
        }
        try {
            await deleteRecord(recordId);
            this.toast('Deleted', `The ${label.toLowerCase()} was deleted.`, 'success');
            this.selectedIds = this.selectedIds.filter((id) => id !== recordId);
            await this.reloadAfterDelete();
        } catch (error) {
            this.toast(`Couldn't delete the ${label.toLowerCase()}`, reduceError(error), 'error');
        }
        this.restoreFocus();
    }

    async handleBulkDelete() {
        const ids = [...this.selectedIds];
        if (!ids.length) {
            return;
        }
        const plural = this.objectLabelPlural.toLowerCase();
        const confirmed = await LightningConfirm.open({
            label: 'Delete selected records',
            message: `Delete ${ids.length} selected ${ids.length === 1 ? this.context.objectLabel.toLowerCase() : plural} on this page? You can't undo this. Records not shown on this page aren't affected.`,
            theme: 'error',
            variant: 'header'
        });
        if (!confirmed) {
            return;
        }
        this.isLoading = true;
        let response;
        try {
            response = await deleteRows({ request: { definitionKey: this.context.definitionKey, parentId: this._recordId, recordIds: ids } });
        } catch (error) {
            this.isLoading = false;
            this.toast('Delete failed', reduceError(error), 'error');
            this.restoreFocus();
            return;
        }
        if (!response || response.status !== STATUS_OK) {
            this.isLoading = false;
            this.toast('Delete failed', (response && response.message) || 'Something went wrong. Try again.', 'error');
            this.restoreFocus();
            return;
        }
        const names = new Map(this.rows.map((r) => [r.id, this.rowName(r)]));
        const failures = (response.results || []).filter((r) => !r.success);
        this.rowErrors = failures.map((f) => ({ id: f.recordId, text: `${names.get(f.recordId) || f.recordId}: ${f.message}` }));
        this.selectedIds = failures.map((f) => f.recordId).filter((id) => names.has(id));
        if (response.failedCount === 0) {
            this.toast('Deleted', `${response.deletedCount} ${response.deletedCount === 1 ? 'record was' : 'records were'} deleted.`, 'success');
        } else if (response.deletedCount === 0) {
            this.toast('Nothing was deleted', `${response.failedCount} ${response.failedCount === 1 ? 'record' : 'records'} couldn't be deleted. See the list for details.`, 'error');
        } else {
            this.toast(
                'Some records were not deleted',
                `${response.deletedCount} deleted, ${response.failedCount} couldn't be deleted. See the list for details.`,
                'warning'
            );
        }
        await this.reloadAfterDelete();
        this.restoreFocus();
    }

    async reloadAfterDelete() {
        await this.load();
        if (this.isOk && this.rows.length === 0 && this.pageIndex > 0) {
            this.pageIndex -= 1;
            await this.load();
        }
    }

    handleDismissRowErrors() {
        this.rowErrors = [];
    }

    async handleRunFlow() {
        const result = await FlowModal.open({
            size: 'medium',
            label: this.flowTitle || 'Run Flow',
            heading: this.flowTitle || 'Run Flow',
            flowApiName: this.context.flowApiName,
            inputVariables: [{ name: 'recordId', type: 'String', value: this._recordId }]
        });
        if (result === 'finished') {
            this.toast('Done', 'The flow finished.', 'success');
            await this.refresh();
        } else if (result === 'error') {
            this.toast('The flow stopped', 'The flow ran into a problem. Contact your Salesforce administrator.', 'error');
        }
        this.restoreFocus();
    }

    // ===== HELPERS =====

    rowName(row) {
        const nameCol = this.columnInfo.find((c) => c.type === 'name' && c.visible) || this.columnInfo.find((c) => c.visible);
        return nameCol && row[nameCol.key] !== undefined ? String(row[nameCol.key]) : undefined;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    announce(text) {
        this.announcement = text || '';
    }

    focusFilterButton() {
        Promise.resolve().then(() => {
            const button = this.template.querySelector('[data-id="filter-toggle"]');
            if (button) {
                button.focus();
            }
        });
    }

    /** After a dialog closes and the list re-renders, keep focus inside the component. */
    restoreFocus() {
        Promise.resolve().then(() => {
            const heading = this.template.querySelector('[data-id="heading"]');
            if (heading && !this.template.activeElement) {
                heading.focus();
            }
        });
    }
}
