import { createElement } from 'lwc';
import ArlFlowModal from 'c/arlFlowModal';

describe('c-arl-flow-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function mount() {
        const element = createElement('c-arl-flow-modal', { is: ArlFlowModal });
        element.flowApiName = 'Contact_Flow';
        element.inputVariables = [{ name: 'recordId', type: 'String', value: '001000000000001AAA' }];
        element.heading = 'Run Flow';
        document.body.appendChild(element);
        return element;
    }

    it('passes the flow name and recordId input', () => {
        const flow = mount().shadowRoot.querySelector('lightning-flow');
        expect(flow.flowApiName).toBe('Contact_Flow');
        expect(flow.flowInputVariables).toEqual([{ name: 'recordId', type: 'String', value: '001000000000001AAA' }]);
    });

    it.each([
        ['FINISHED', 'finished'],
        ['FINISHED_SCREEN', 'finished'],
        ['ERROR', 'error']
    ])('closes on %s with %s', (status, expected) => {
        const element = mount();
        const results = [];
        element.addEventListener('modalclose', (e) => results.push(e.detail));
        element.shadowRoot.querySelector('lightning-flow').dispatchEvent(new CustomEvent('statuschange', { detail: { status } }));
        expect(results).toEqual([expected]);
    });

    it('stays open while the flow is running', () => {
        const element = mount();
        const results = [];
        element.addEventListener('modalclose', (e) => results.push(e.detail));
        element.shadowRoot.querySelector('lightning-flow').dispatchEvent(new CustomEvent('statuschange', { detail: { status: 'STARTED' } }));
        expect(results).toEqual([]);
    });
});
