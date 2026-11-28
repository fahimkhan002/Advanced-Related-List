import { LightningElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccess from '@salesforce/apex/RelatedListBuilderController.getAccess';
import listDefinitions from '@salesforce/apex/RelatedListBuilderController.listDefinitions';
import getDefinition from '@salesforce/apex/RelatedListBuilderController.getDefinition';
import listObjects from '@salesforce/apex/RelatedListBuilderController.listObjects';
import listRelationships from '@salesforce/apex/RelatedListBuilderController.listRelationships';
import listFields from '@salesforce/apex/RelatedListBuilderController.listFields';
import listFlows from '@salesforce/apex/RelatedListBuilderController.listFlows';
import listQuickActions from '@salesforce/apex/RelatedListBuilderController.listQuickActions';
import validateDraft from '@salesforce/apex/RelatedListBuilderController.validateDraft';
import saveDraft from '@salesforce/apex/RelatedListBuilderController.saveDraft';
import getSignature from '@salesforce/apex/RelatedListBuilderController.getSignature';
import { reduceError } from 'c/arlUtils';

const POLL_MS = 2000;
const POLL_LIMIT = 45;
const MAX_COLUMNS = 25;
const MAX_ACTIONS = 10;
const MAX_OBJECT_OPTIONS = 200;
const FLAGS = ['visible', 'searchable', 'filterable', 'sortable', 'editable'];

let rowSeq = 0;
const nextRowId = () => `row${++rowSeq}`;

/** Mirrors RelatedListBuilderService.developerNameFrom so the suggested API name matches the server. */
export function toDeveloperName(label) {
    let s = (label || '').replace(/[^A-Za-z0-9]+/g, '_').replace(/_+/g, '_').replace(/^_/, '');
    if (!s || !/^[A-Za-z]/.test(s)) {
        s = `L_${s}`;
    }
    return s.slice(0, 40).replace(/_+$/, '');
}

/**
 * Tekenable Related List Builder: creates and maintains Tekenable Advance Related List definitions without editing
 * source or typing API names. Saves through RelatedListBuilderController (Apex Metadata API).
 */
export default class ArlListBuilder extends LightningElement {
    access;
    isLoading = true;
    error;

    definitions = [];
    listSearch = '';
    selectedKey;

    draft;
    dirty = false;
    apiNameEdited = false;

    objects = [];
    objectSearch = '';
    relationships = [];
    flows = [];
    fieldsCache = {};
    quickActionsCache = {};

    showPicker = false;
    isBusy = false;
    issues = [];
    issuesStale = false;
    saveState = 'idle';
    saveMessage = '';
    pendingSignature;
    pollTimer;
    pollCount = 0;

    // ===== LIFECYCLE =====

    async connectedCallback() {
        try {
            this.access = await getAccess();
            if (this.access && this.access.canManage) {
                await Promise.all([this.loadDefinitions(), this.loadObjects(), this.loadFlows()]);
            }
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        clearTimeout(this.pollTimer);
    }

    async loadDefinitions() {
        this.definitions = await listDefinitions();
    }

    async loadObjects() {
        this.objects = await listObjects();
    }

    async loadFlows() {
        try {
            this.flows = await listFlows();
        } catch {
            this.flows = [];
        }
    }

    async fieldsFor(objectApiName) {
        if (!this.fieldsCache[objectApiName]) {
            this.fieldsCache = { ...this.fieldsCache, [objectApiName]: await listFields({ objectApiName }) };
        }
        return this.fieldsCache[objectApiName];
    }

    // ===== ACCESS / STATES =====

    get canManage() {
        return Boolean(this.access && this.access.canManage);
    }

    get accessReason() {
        return this.access ? this.access.reason : '';
    }

    get showNoAccess() {
        return !this.isLoading && !this.error && !this.canManage;
    }

    get showBuilder() {
        return !this.isLoading && this.canManage;
    }

    get hasDraft() {
        return Boolean(this.draft);
    }

    // ===== DEFINITION LIST =====

    get filteredDefinitions() {
        const term = this.listSearch.trim().toLowerCase();
        return this.definitions
            .filter((d) => !term || `${d.label} ${d.developerName} ${d.childObject}`.toLowerCase().includes(term))
            .map((d) => ({
                ...d,
                selected: d.developerName === this.selectedKey,
                itemClass: `slds-nav-vertical__item${d.developerName === this.selectedKey ? ' slds-is-active' : ''}`,
                summary: `${d.childObject || '?'} via ${d.lookupField || '?'} · ${d.columnCount} column${d.columnCount === 1 ? '' : 's'}`,
                ariaCurrent: d.developerName === this.selectedKey ? 'page' : null
            }));
    }

    get hasDefinitions() {
        return this.filteredDefinitions.length > 0;
    }

    handleListSearch(event) {
        this.listSearch = event.target.value || '';
    }

    async confirmDiscard() {
        if (!this.dirty) {
            return true;
        }
        return LightningConfirm.open({
            label: 'Discard unsaved changes?',
            message: 'You have changes that are not saved. Discard them?',
            theme: 'warning',
            variant: 'header'
        });
    }

    async handleSelectDefinition(event) {
        event.preventDefault();
        const key = event.currentTarget.dataset.key;
        if (key === this.selectedKey && this.draft) {
            return;
        }
        if (!(await this.confirmDiscard())) {
            return;
        }
        await this.openDefinition(key);
    }

    async openDefinition(key) {
        this.isBusy = true;
        try {
            const def = await getDefinition({ developerName: key });
            this.selectedKey = key;
            this.draft = {
                ...def,
                isNew: false,
                columns: (def.columns || []).map((c) => ({ ...c, rowId: nextRowId(), meta: null, labelHint: c.fieldPath })),
                actions: (def.actions || []).map((a) => ({ ...a, rowId: nextRowId(), label: a.label || '' }))
            };
            this.resetEditorState();
            if (this.draft.parentObject) {
                await this.loadRelationships(this.draft.parentObject);
            }
            await this.resolveAllColumnMeta();
            await this.ensureQuickActionsLoaded();
        } catch (e) {
            this.toast('Could not open the list', reduceError(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleNew() {
        if (!(await this.confirmDiscard())) {
            return;
        }
        this.selectedKey = undefined;
        this.draft = {
            isNew: true,
            label: '',
            developerName: '',
            active: true,
            parentObject: '',
            childObject: '',
            lookupField: '',
            defaultSortField: '',
            defaultSortDirection: 'ASC',
            allowCreate: true,
            allowEdit: true,
            allowDelete: true,
            allowBulkDelete: false,
            flowApiName: '',
            columns: [],
            actions: [{ rowId: nextRowId(), developerName: null, actionType: 'Standard', target: 'New', label: '', placement: 'List', display: 'Button' }]
        };
        this.relationships = [];
        this.resetEditorState();
        this.focusLater('[data-id="label"]');
    }

    resetEditorState() {
        this.dirty = false;
        this.apiNameEdited = false;
        this.issues = [];
        this.issuesStale = false;
        this.showPicker = false;
        this.saveState = 'idle';
        this.saveMessage = '';
        clearTimeout(this.pollTimer);
    }

    // ===== DRAFT EDITING =====

    update(changes) {
        this.draft = { ...this.draft, ...changes };
        this.dirty = true;
        this.issuesStale = this.issues.length > 0;
        if (this.saveState === 'saved' || this.saveState === 'timeout') {
            this.saveState = 'idle';
            this.saveMessage = '';
        }
    }

    get isNew() {
        return Boolean(this.draft && this.draft.isNew);
    }

    get apiNameDisabled() {
        return !this.isNew;
    }

    get editorHeading() {
        if (!this.draft) {
            return '';
        }
        return this.isNew ? 'New related list' : this.draft.label;
    }

    handleLabel(event) {
        const label = event.target.value || '';
        const changes = { label };
        if (this.isNew && !this.apiNameEdited) {
            changes.developerName = toDeveloperName(label);
        }
        this.update(changes);
    }

    handleApiName(event) {
        this.apiNameEdited = true;
        this.update({ developerName: event.target.value || '' });
    }

    handleActive(event) {
        this.update({ active: event.target.checked });
    }

    // ----- relationship -----

    get objectOptions() {
        const term = this.objectSearch.trim().toLowerCase();
        const matches = this.objects.filter((o) => !term || o.label.toLowerCase().includes(term) || o.value.toLowerCase().includes(term));
        const options = matches.slice(0, MAX_OBJECT_OPTIONS).map((o) => ({ label: `${o.label} (${o.value})`, value: o.value }));
        const current = this.draft && this.draft.parentObject;
        if (current && !options.some((o) => o.value === current)) {
            const found = this.objects.find((o) => o.value === current);
            options.unshift({ label: found ? `${found.label} (${found.value})` : current, value: current });
        }
        return options;
    }

    get objectMatchText() {
        const term = this.objectSearch.trim().toLowerCase();
        const count = this.objects.filter((o) => !term || o.label.toLowerCase().includes(term) || o.value.toLowerCase().includes(term)).length;
        return count > MAX_OBJECT_OPTIONS ? `Showing ${MAX_OBJECT_OPTIONS} of ${count} objects. Type to narrow the list.` : `${count} objects`;
    }

    handleObjectSearch(event) {
        this.objectSearch = event.target.value || '';
    }

    async handleParentChange(event) {
        const parentObject = event.detail.value;
        if (parentObject === this.draft.parentObject) {
            return;
        }
        this.update({ parentObject, childObject: '', lookupField: '', columns: [], defaultSortField: '', actions: this.clearQuickTargets() });
        this.showPicker = false;
        await this.loadRelationships(parentObject);
    }

    async loadRelationships(parentObject) {
        try {
            this.relationships = await listRelationships({ parentObject });
        } catch (e) {
            this.relationships = [];
            this.toast('Could not load related objects', reduceError(e), 'error');
        }
    }

    get relationshipOptions() {
        return this.relationships.map((r) => ({ label: r.label, value: r.value, description: r.value }));
    }

    get relationshipValue() {
        return this.draft && this.draft.childObject && this.draft.lookupField ? `${this.draft.childObject}.${this.draft.lookupField}` : '';
    }

    get relationshipDisabled() {
        return !this.draft || !this.draft.parentObject;
    }

    get relationshipHelp() {
        if (!this.relationshipValue) {
            return 'Choose the related records to show. Each option is one lookup, so two lookups to the same object appear separately.';
        }
        const r = this.relationships.find((x) => x.value === this.relationshipValue);
        return r ? `Shows ${r.childLabel} whose "${r.lookupLabel}" is this record (${r.value}).` : this.relationshipValue;
    }

    get childLabel() {
        const r = this.relationships.find((x) => x.value === this.relationshipValue);
        return r ? r.childLabel : this.draft && this.draft.childObject;
    }

    handleRelationshipChange(event) {
        const r = this.relationships.find((x) => x.value === event.detail.value);
        if (!r) {
            return;
        }
        const childChanged = r.childObject !== this.draft.childObject;
        this.update({
            childObject: r.childObject,
            lookupField: r.lookupField,
            columns: childChanged ? [] : this.draft.columns,
            defaultSortField: childChanged ? '' : this.draft.defaultSortField,
            actions: childChanged ? this.clearQuickTargets('Row') : this.draft.actions
        });
        this.showPicker = false;
    }

    // ----- columns -----

    get hasRelationship() {
        return Boolean(this.relationshipValue);
    }

    get hasColumns() {
        return Boolean(this.draft && this.draft.columns.length);
    }

    get addColumnDisabled() {
        return !this.hasRelationship || this.showPicker || this.draft.columns.length >= MAX_COLUMNS;
    }

    get usedPaths() {
        return this.draft ? this.draft.columns.map((c) => c.fieldPath) : [];
    }

    get columnRows() {
        const cols = this.draft ? this.draft.columns : [];
        const issuesByIndex = {};
        this.issues.forEach((i) => {
            if (i.columnIndex !== null && i.columnIndex !== undefined) {
                (issuesByIndex[i.columnIndex] = issuesByIndex[i.columnIndex] || []).push(i);
            }
        });
        return cols.map((c, index) => {
            const meta = c.meta;
            const name = c.label || c.labelHint || c.fieldPath;
            const unsupported = (ok, verb) => (meta && !ok ? `This field type can't be ${verb}.` : '');
            return {
                ...c,
                index,
                position: index + 1,
                displayName: name,
                rowIssues: (issuesByIndex[index] || []).map((i, n) => ({ key: `${index}-${n}`, text: i.message, className: i.severity === 'error' ? 'slds-text-color_error' : 'slds-text-color_weak' })),
                hasRowIssues: Boolean(issuesByIndex[index]),
                labelInputLabel: `Column label for ${name}`,
                labelPlaceholder: c.labelHint || c.fieldPath,
                visibleLabel: `Show ${name}`,
                searchLabel: `Search ${name}`,
                filterLabel: `Filter by ${name}`,
                sortLabel: `Sort by ${name}`,
                editLabel: `Edit ${name}`,
                searchDisabled: Boolean(meta && !meta.canSearch),
                filterDisabled: Boolean(meta && !meta.canFilter),
                sortDisabled: Boolean(meta && !meta.canSort),
                editDisabled: Boolean(meta && !meta.canEdit),
                searchTitle: unsupported(meta && meta.canSearch, 'searched'),
                filterTitle: unsupported(meta && meta.canFilter, 'filtered'),
                sortTitle: unsupported(meta && meta.canSort, 'sorted'),
                editTitle: meta && !meta.canEdit ? 'Only fields on the related object that you can edit can be made editable.' : '',
                upDisabled: index === 0,
                downDisabled: index === cols.length - 1,
                upLabel: `Move ${name} up`,
                downLabel: `Move ${name} down`,
                removeLabel: `Remove ${name}`
            };
        });
    }

    handleAddColumn() {
        this.showPicker = true;
    }

    handlePickerCancel() {
        this.showPicker = false;
        this.focusLater('[data-id="add-column"]');
    }

    handlePickerSelect(event) {
        const { path, labelHint, meta } = event.detail;
        if (this.draft.columns.length >= MAX_COLUMNS) {
            return;
        }
        const row = {
            rowId: nextRowId(),
            developerName: null,
            fieldPath: path,
            label: '',
            labelHint,
            meta,
            visible: true,
            searchable: false,
            filterable: false,
            sortable: false,
            editable: false
        };
        this.update({ columns: [...this.draft.columns, row] });
        this.showPicker = false;
        this.focusLater('[data-id="add-column"]');
    }

    updateColumn(rowId, changes) {
        this.update({ columns: this.draft.columns.map((c) => (c.rowId === rowId ? { ...c, ...changes } : c)) });
    }

    handleColumnLabel(event) {
        this.updateColumn(event.target.dataset.row, { label: event.target.value || '' });
    }

    handleColumnFlag(event) {
        const flag = event.target.dataset.flag;
        if (FLAGS.includes(flag)) {
            this.updateColumn(event.target.dataset.row, { [flag]: event.target.checked });
        }
    }

    handleMove(event) {
        const index = Number(event.currentTarget.dataset.index);
        const delta = event.currentTarget.dataset.direction === 'up' ? -1 : 1;
        const target = index + delta;
        const cols = [...this.draft.columns];
        if (target < 0 || target >= cols.length) {
            return;
        }
        [cols[index], cols[target]] = [cols[target], cols[index]];
        this.update({ columns: cols });
        this.focusLater(`[data-direction="${event.currentTarget.dataset.direction}"][data-index="${target}"]`);
    }

    handleRemove(event) {
        const rowId = event.currentTarget.dataset.row;
        const removed = this.draft.columns.find((c) => c.rowId === rowId);
        const columns = this.draft.columns.filter((c) => c.rowId !== rowId);
        const changes = { columns };
        if (removed && removed.fieldPath === this.draft.defaultSortField) {
            changes.defaultSortField = '';
        }
        this.update(changes);
        this.focusLater('[data-id="add-column"]');
    }

    async resolveAllColumnMeta() {
        const resolved = await Promise.all(this.draft.columns.map((c) => this.resolveMeta(c.fieldPath).catch(() => null)));
        this.draft = {
            ...this.draft,
            columns: this.draft.columns.map((c, i) => ({ ...c, meta: resolved[i] ? resolved[i].meta : null, labelHint: resolved[i] ? resolved[i].labelHint : c.fieldPath }))
        };
    }

    /** Walks a field path through the cached describes to recover its capabilities. */
    async resolveMeta(path) {
        const segments = (path || '').split('.');
        let objectApiName = this.draft.childObject;
        let objectLabel = null;
        for (let i = 0; i < segments.length - 1; i++) {
            // eslint-disable-next-line no-await-in-loop
            const fields = await this.fieldsFor(objectApiName);
            const hop = fields.find((f) => f.relationshipName && f.relationshipName.toLowerCase() === segments[i].toLowerCase());
            if (!hop) {
                return null;
            }
            objectApiName = hop.targetObject;
            objectLabel = hop.targetLabel;
        }
        const fields = await this.fieldsFor(objectApiName);
        const field = fields.find((f) => f.apiName.toLowerCase() === segments[segments.length - 1].toLowerCase());
        if (!field) {
            return null;
        }
        const depth = segments.length - 1;
        return {
            labelHint: depth ? `${objectLabel}: ${field.label}` : field.label,
            meta: { type: field.type, canSearch: field.canSearch, canFilter: field.canFilter, canSort: field.canSort, canEdit: field.canEdit && depth === 0 }
        };
    }

    // ----- sort, actions, flow -----

    get sortOptions() {
        const options = [{ label: 'Record ID (no default sort)', value: '' }];
        (this.draft ? this.draft.columns : []).forEach((c) => {
            if (!c.meta || c.meta.canSort) {
                options.push({ label: c.label || c.labelHint || c.fieldPath, value: c.fieldPath });
            }
        });
        if (this.draft && this.draft.defaultSortField && !options.some((o) => o.value === this.draft.defaultSortField)) {
            options.push({ label: this.draft.defaultSortField, value: this.draft.defaultSortField });
        }
        return options;
    }

    get directionOptions() {
        return [
            { label: 'Ascending', value: 'ASC' },
            { label: 'Descending', value: 'DESC' }
        ];
    }

    get sortDirectionDisabled() {
        return !this.draft || !this.draft.defaultSortField;
    }

    handleSortField(event) {
        this.update({ defaultSortField: event.detail.value });
    }

    handleSortDirection(event) {
        this.update({ defaultSortDirection: event.detail.value });
    }

    handleActionFlag(event) {
        this.update({ [event.target.dataset.flag]: event.target.checked });
    }

    get sortValue() {
        return (this.draft && this.draft.defaultSortField) || '';
    }

    // ----- actions (flows and quick actions) -----

    get typeOptions() {
        return [
            { label: 'Screen flow', value: 'Flow' },
            { label: 'Quick action', value: 'Quick_Action' },
            { label: 'Standard: New button', value: 'Standard' }
        ];
    }

    get displayOptions() {
        return [
            { label: 'Button', value: 'Button' },
            { label: 'More menu', value: 'Menu' },
            { label: 'Automatic (first two are buttons)', value: '' }
        ];
    }

    get placementOptions() {
        return [
            { label: 'List header button (runs for this record)', value: 'List' },
            { label: 'Row menu item (runs for each related record)', value: 'Row' }
        ];
    }

    get hasActions() {
        return Boolean(this.draft && this.draft.actions && this.draft.actions.length);
    }

    get addActionDisabled() {
        return !this.hasRelationship || (this.draft && this.draft.actions.length >= MAX_ACTIONS);
    }

    contextObjectFor(placement) {
        return placement === 'Row' ? this.draft.childObject : this.draft.parentObject;
    }

    targetOptionsFor(action) {
        if (action.actionType === 'Standard') {
            return [{ label: 'New record', value: 'New' }];
        }
        if (action.actionType === 'Flow') {
            const options = this.flows.map((f) => ({ label: `${f.label} (${f.value})`, value: f.value }));
            if (action.target && !options.some((o) => o.value === action.target)) {
                options.push({ label: `${action.target} (not active)`, value: action.target });
            }
            return options;
        }
        const objectApiName = this.contextObjectFor(action.placement);
        const options = (this.quickActionsCache[objectApiName] || []).map((q) => ({ label: `${q.label} (${q.value})`, value: q.value }));
        if (action.target && !options.some((o) => o.value === action.target)) {
            options.push({ label: action.target, value: action.target });
        }
        return options;
    }

    get actionRows() {
        const actions = this.draft ? this.draft.actions : [];
        return actions.map((a, index) => {
            const name = a.label || a.target || `Action ${index + 1}`;
            const issues = this.issues
                .filter((i) => i.actionIndex === index)
                .map((i, n) => ({ key: `a${index}-${n}`, text: i.message, className: i.severity === 'error' ? 'slds-text-color_error' : 'slds-text-color_weak' }));
            return {
                ...a,
                index,
                position: index + 1,
                targetOptions: this.targetOptionsFor(a),
                targetPlaceholder: a.actionType === 'Flow' ? 'Choose an active screen flow' : 'Choose a quick action',
                isStandard: a.actionType === 'Standard',
                placementDisabled: a.actionType === 'Standard',
                displayValue: a.placement === 'Row' ? '' : a.display || '',
                displayDisabled: a.placement === 'Row',
                rowDisplayOptions: a.placement === 'Row' ? [{ label: "In each row's menu", value: '' }] : this.displayOptions,
                displayLabel: `How action ${index + 1} is shown`,
                labelPlaceholder: a.actionType === 'Standard' ? 'New' : 'Default label',
                typeLabel: `Type of action ${index + 1}`,
                placementLabel: `Where action ${index + 1} appears`,
                targetLabel: `What action ${index + 1} runs`,
                labelLabel: `Button label for action ${index + 1}`,
                upLabel: `Move ${name} up`,
                downLabel: `Move ${name} down`,
                removeLabel: `Remove ${name}`,
                upDisabled: index === 0,
                downDisabled: index === actions.length - 1,
                rowIssues: issues,
                hasRowIssues: issues.length > 0
            };
        });
    }

    /** Quick actions belong to one object; when that object changes they must be chosen again. */
    clearQuickTargets(placement) {
        return (this.draft.actions || []).map((a) => (a.actionType === 'Quick_Action' && (!placement || a.placement === placement) ? { ...a, target: '' } : a));
    }

    async loadQuickActions(objectApiName) {
        if (!objectApiName || this.quickActionsCache[objectApiName]) {
            return;
        }
        try {
            const actions = await listQuickActions({ objectApiName });
            this.quickActionsCache = { ...this.quickActionsCache, [objectApiName]: actions };
        } catch (e) {
            this.toast('Could not load quick actions', reduceError(e), 'error');
        }
    }

    async ensureQuickActionsLoaded() {
        const needed = new Set((this.draft.actions || []).filter((a) => a.actionType === 'Quick_Action').map((a) => this.contextObjectFor(a.placement)));
        await Promise.all([...needed].map((o) => this.loadQuickActions(o)));
    }

    updateAction(rowId, changes) {
        this.update({ actions: this.draft.actions.map((a) => (a.rowId === rowId ? { ...a, ...changes } : a)) });
    }

    handleAddAction() {
        const row = { rowId: nextRowId(), developerName: null, actionType: 'Flow', target: '', label: '', placement: 'List', display: 'Button' };
        this.update({ actions: [...this.draft.actions, row] });
        this.focusLater(`[data-row="${row.rowId}"][data-role="action-target"]`);
    }

    async handleActionType(event) {
        const rowId = event.target.dataset.row;
        const actionType = event.detail.value;
        // The New button is a list header action; the others start empty.
        this.updateAction(rowId, actionType === 'Standard' ? { actionType, target: 'New', placement: 'List' } : { actionType, target: '' });
        await this.ensureQuickActionsLoaded();
    }

    async handleActionPlacement(event) {
        const rowId = event.target.dataset.row;
        const current = this.draft.actions.find((a) => a.rowId === rowId);
        // A quick action belongs to one object: changing where it runs means choosing again.
        const changes = { placement: event.detail.value };
        if (current && current.actionType === 'Quick_Action') {
            changes.target = '';
        }
        this.updateAction(rowId, changes);
        await this.ensureQuickActionsLoaded();
    }

    handleActionTarget(event) {
        this.updateAction(event.target.dataset.row, { target: event.detail.value });
    }

    handleActionDisplay(event) {
        this.updateAction(event.target.dataset.row, { display: event.detail.value || null });
    }

    handleActionLabel(event) {
        this.updateAction(event.target.dataset.row, { label: event.target.value || '' });
    }

    handleActionMove(event) {
        const index = Number(event.currentTarget.dataset.index);
        const delta = event.currentTarget.dataset.direction === 'up' ? -1 : 1;
        const target = index + delta;
        const actions = [...this.draft.actions];
        if (target < 0 || target >= actions.length) {
            return;
        }
        [actions[index], actions[target]] = [actions[target], actions[index]];
        this.update({ actions });
    }

    handleActionRemove(event) {
        const rowId = event.currentTarget.dataset.row;
        this.update({ actions: this.draft.actions.filter((a) => a.rowId !== rowId) });
        this.focusLater('[data-id="add-action"]');
    }

    // ===== VALIDATE / SAVE =====

    toServerDraft() {
        const d = this.draft;
        return {
            developerName: d.developerName,
            isNew: d.isNew,
            label: d.label,
            active: d.active,
            parentObject: d.parentObject,
            childObject: d.childObject,
            lookupField: d.lookupField,
            defaultSortField: d.defaultSortField || null,
            defaultSortDirection: d.defaultSortDirection,
            allowCreate: (d.actions || []).some((a) => a.actionType === 'Standard'),
            allowEdit: d.allowEdit,
            allowDelete: d.allowDelete,
            allowBulkDelete: d.allowBulkDelete,
            flowApiName: null,
            actions: (d.actions || []).map((a) => ({
                developerName: a.developerName || null,
                actionType: a.actionType,
                target: a.target || null,
                label: a.label || null,
                placement: a.placement,
                display: a.placement === 'Row' ? null : a.display || null
            })),
            columns: d.columns.map((c) => ({
                developerName: c.developerName || null,
                fieldPath: c.fieldPath,
                label: c.label || null,
                visible: c.visible,
                searchable: c.searchable,
                filterable: c.filterable,
                sortable: c.sortable,
                editable: c.editable
            }))
        };
    }

    get errors() {
        return this.issues.filter((i) => i.severity === 'error' && (i.columnIndex === null || i.columnIndex === undefined) && (i.actionIndex === null || i.actionIndex === undefined));
    }

    get warnings() {
        return this.issues.filter(
            (i) => i.severity !== 'error' && (i.columnIndex === null || i.columnIndex === undefined) && (i.actionIndex === null || i.actionIndex === undefined)
        );
    }

    get errorCount() {
        return this.issues.filter((i) => i.severity === 'error').length;
    }

    get hasErrors() {
        return this.errors.length > 0;
    }

    get hasWarnings() {
        return this.warnings.length > 0;
    }

    get hasIssues() {
        return this.issues.length > 0;
    }

    get isWorking() {
        return this.saveState === 'validating' || this.saveState === 'saving' || this.saveState === 'deploying';
    }

    get saveDisabled() {
        return !this.draft || this.isWorking || (!this.dirty && !this.isNew);
    }

    get statusClass() {
        const base = 'slds-text-body_small slds-m-left_small';
        if (this.saveState === 'saved') {
            return `${base} slds-text-color_success`;
        }
        if (this.saveState === 'timeout' || this.saveState === 'invalid') {
            return `${base} slds-text-color_error`;
        }
        return base;
    }

    get showDeploySpinner() {
        return this.saveState === 'deploying' || this.saveState === 'saving';
    }

    get savedKeyHint() {
        return this.saveState === 'saved' && this.draft ? this.draft.developerName : null;
    }

    async handleValidate() {
        this.saveState = 'validating';
        this.saveMessage = 'Checking…';
        try {
            const result = await validateDraft({ draft: this.toServerDraft() });
            this.issues = result.issues || [];
            this.issuesStale = false;
            this.saveState = result.valid ? 'idle' : 'invalid';
            this.saveMessage = result.valid ? 'No problems found.' : `${this.errorCount} problem(s) to fix before saving.`;
        } catch (e) {
            this.saveState = 'invalid';
            this.saveMessage = reduceError(e);
        }
        this.focusLater('[data-id="status"]');
    }

    async handleSave() {
        this.saveState = 'saving';
        this.saveMessage = 'Saving…';
        let result;
        try {
            result = await saveDraft({ draft: this.toServerDraft() });
        } catch (e) {
            this.saveState = 'invalid';
            this.saveMessage = reduceError(e);
            return;
        }
        this.issues = result.issues || [];
        this.issuesStale = false;
        if (result.status !== 'QUEUED') {
            this.saveState = 'invalid';
            this.saveMessage = `${this.errorCount} problem(s) to fix before saving.`;
            this.focusLater('[data-id="status"]');
            return;
        }
        this.pendingSignature = result.signature;
        this.draft = { ...this.draft, developerName: result.developerName };
        this.saveState = 'deploying';
        this.saveMessage = 'Deploying… this usually takes a few seconds.';
        this.pollCount = 0;
        this.poll();
    }

    poll() {
        clearTimeout(this.pollTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.pollTimer = setTimeout(async () => {
            this.pollCount += 1;
            let signature = null;
            try {
                signature = await getSignature({ developerName: this.draft.developerName });
            } catch {
                signature = null;
            }
            if (signature && signature === this.pendingSignature) {
                await this.onDeployed();
            } else if (this.pollCount < POLL_LIMIT) {
                this.poll();
            } else {
                this.saveState = 'timeout';
                this.saveMessage = 'The deployment has not finished yet. Check Setup > Deployment Status, then reload this list.';
            }
        }, POLL_MS);
    }

    async onDeployed() {
        const key = this.draft.developerName;
        this.toast('Saved', `"${this.draft.label}" is saved.`, 'success');
        await this.loadDefinitions();
        await this.openDefinition(key);
        this.saveState = 'saved';
        this.saveMessage = 'Saved.';
        this.focusLater('[data-id="status"]');
    }

    // ===== HELPERS =====

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    focusLater(selector) {
        Promise.resolve().then(() => {
            const el = this.template.querySelector(selector);
            if (el) {
                el.focus();
            }
        });
    }
}
