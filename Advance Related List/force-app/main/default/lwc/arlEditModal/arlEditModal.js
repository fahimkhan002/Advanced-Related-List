import { api } from 'lwc';
import LightningModal from 'lightning/modal';

/**
 * Single-record edit through Lightning Data Service. LDS enforces object, field and record access
 * and record-level validation; nothing here grants access. LightningModal provides the focus trap,
 * Escape handling and focus return to the control that opened it.
 */
export default class ArlEditModal extends LightningModal {
    @api recordId;
    @api objectApiName;
    /** Field API names configured as editable; empty uses the page layout. */
    @api fields;
    @api heading;

    get hasFields() {
        return Array.isArray(this.fields) && this.fields.length > 0;
    }

    get layoutType() {
        return this.hasFields ? undefined : 'Full';
    }

    get formFields() {
        return this.hasFields ? this.fields : undefined;
    }

    handleSuccess() {
        this.close('saved');
    }

    handleCancel() {
        this.close('cancel');
    }
}
