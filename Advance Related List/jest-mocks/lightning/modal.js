import { LightningElement, api } from 'lwc';

/** Minimal LightningModal stand-in: records close() results for assertions. */
export default class LightningModal extends LightningElement {
    @api size;
    @api label;
    @api description;
    @api disableClose;

    static open() {
        return Promise.resolve();
    }

    close(result) {
        this.dispatchEvent(new CustomEvent('modalclose', { detail: result }));
    }
}
