import { LightningElement, api } from 'lwc';
import listFields from '@salesforce/apex/RelatedListBuilderController.listFields';
import { reduceError } from 'c/arlUtils';

const MAX_HOPS = 5;

/**
 * Field picker for the Tekenable Related List Builder. Lists readable fields of an object, lets the admin
 * follow single-target lookups (up to 5 hops, the limit the list enforces) and returns a field path
 * such as "Account.Owner.Name" together with what the list can do with that field.
 * Events: `select` { path, labelHint, meta }, `cancel`.
 */
export default class ArlFieldPicker extends LightningElement {
    @api rootObject;
    @api rootLabel;
    /** Paths already used, shown as "Added". */
    @api usedPaths = [];

    hops = [];
    fields = [];
    searchText = '';
    isLoading = false;
    error;

    connectedCallback() {
        this.hops = [{ objectApiName: this.rootObject, label: this.rootLabel || this.rootObject, relationshipName: null }];
        this.load();
    }

    get current() {
        return this.hops[this.hops.length - 1];
    }

    get depth() {
        return this.hops.length - 1;
    }

    get breadcrumbs() {
        return this.hops.map((h, index) => ({ key: `${index}-${h.objectApiName}`, label: h.label, index }));
    }

    get pathPrefix() {
        return this.hops
            .slice(1)
            .map((h) => h.relationshipName)
            .join('.');
    }

    get heading() {
        return `Choose a field from ${this.current.label}`;
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            this.fields = await listFields({ objectApiName: this.current.objectApiName });
        } catch (e) {
            this.fields = [];
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get visibleFields() {
        const term = this.searchText.trim().toLowerCase();
        const used = new Set((this.usedPaths || []).map((p) => p.toLowerCase()));
        const prefix = this.pathPrefix;
        return this.fields
            .filter((f) => !term || f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term))
            .map((f) => {
                const path = prefix ? `${prefix}.${f.apiName}` : f.apiName;
                const abilities = [f.canSearch ? 'search' : null, f.canFilter ? 'filter' : null, f.canSort ? 'sort' : null].filter(Boolean);
                return {
                    ...f,
                    path,
                    added: used.has(path.toLowerCase()),
                    selectLabel: `Add ${f.label}`,
                    canDrill: Boolean(f.targetObject) && this.depth < MAX_HOPS,
                    drillLabel: `Show fields of ${f.targetLabel || ''} (${f.label})`,
                    abilityText: abilities.length ? `Can ${abilities.join(', ')}` : 'Display only'
                };
            });
    }

    get hasFields() {
        return this.visibleFields.length > 0;
    }

    handleSearch(event) {
        this.searchText = event.target.value || '';
    }

    handleDrill(event) {
        const field = this.fields.find((f) => f.apiName === event.currentTarget.dataset.api);
        if (!field || !field.targetObject) {
            return;
        }
        this.hops = [...this.hops, { objectApiName: field.targetObject, label: field.targetLabel, relationshipName: field.relationshipName }];
        this.searchText = '';
        this.load();
    }

    handleCrumb(event) {
        event.preventDefault();
        const index = Number(event.currentTarget.dataset.index);
        if (index < this.hops.length - 1) {
            this.hops = this.hops.slice(0, index + 1);
            this.searchText = '';
            this.load();
        }
    }

    handleSelect(event) {
        const field = this.visibleFields.find((f) => f.apiName === event.currentTarget.dataset.api);
        if (!field) {
            return;
        }
        const viaRelationship = this.depth > 0;
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: {
                    path: field.path,
                    labelHint: viaRelationship ? `${this.current.label}: ${field.label}` : field.label,
                    meta: {
                        type: field.type,
                        canSearch: field.canSearch,
                        canFilter: field.canFilter,
                        canSort: field.canSort,
                        canEdit: field.canEdit && !viaRelationship
                    }
                }
            })
        );
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleCancel();
        }
    }
}
