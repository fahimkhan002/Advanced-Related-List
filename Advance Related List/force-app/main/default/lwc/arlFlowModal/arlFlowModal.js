import { api } from 'lwc';
import LightningModal from 'lightning/modal';

const FINISHED = new Set(['FINISHED', 'FINISHED_SCREEN']);

/**
 * Runs the configured screen flow with the parent record ID. The flow runs in its own configured
 * context and with its own access checks; launching it grants nothing.
 * Resolves with 'finished', 'error' or undefined (closed by the user).
 */
export default class ArlFlowModal extends LightningModal {
    @api flowApiName;
    @api inputVariables;
    @api heading;

    handleStatusChange(event) {
        const status = event.detail && event.detail.status;
        if (FINISHED.has(status)) {
            this.close('finished');
        } else if (status === 'ERROR') {
            this.close('error');
        }
    }
}
