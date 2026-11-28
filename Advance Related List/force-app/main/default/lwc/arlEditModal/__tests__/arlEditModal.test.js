import { createElement } from 'lwc';
import ArlEditModal from 'c/arlEditModal';

describe('c-arl-edit-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function mount(props) {
        const element = createElement('c-arl-edit-modal', { is: ArlEditModal });
        Object.assign(element, { recordId: '003000000000001AAA', objectApiName: 'Contact', heading: 'Edit Contact' }, props);
        document.body.appendChild(element);
        return element;
    }

    it('edits only the configured fields', () => {
        const element = mount({ fields: ['Email', 'Title'] });
        const form = element.shadowRoot.querySelector('lightning-record-form');
        expect(form.fields).toEqual(['Email', 'Title']);
        expect(form.layoutType).toBeUndefined();
        expect(form.mode).toBe('edit');
        expect(form.recordId).toBe('003000000000001AAA');
        expect(element.shadowRoot.querySelector('lightning-modal-header').label).toBe('Edit Contact');
    });

    it('falls back to the page layout when no fields are configured', () => {
        const element = mount({ fields: [] });
        const form = element.shadowRoot.querySelector('lightning-record-form');
        expect(form.fields).toBeUndefined();
        expect(form.layoutType).toBe('Full');
    });

    it('closes with saved on success and cancel on cancel', () => {
        const element = mount({ fields: ['Email'] });
        const results = [];
        element.addEventListener('modalclose', (e) => results.push(e.detail));
        const form = element.shadowRoot.querySelector('lightning-record-form');
        form.dispatchEvent(new CustomEvent('success'));
        form.dispatchEvent(new CustomEvent('cancel'));
        expect(results).toEqual(['saved', 'cancel']);
    });
});
