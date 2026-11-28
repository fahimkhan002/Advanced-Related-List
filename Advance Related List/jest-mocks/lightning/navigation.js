import { createTestWireAdapter } from '@salesforce/wire-service-jest-util';

export const CurrentPageReference = createTestWireAdapter(jest.fn());

let navigateCalls = [];

const Navigate = Symbol('Navigate');
const GenerateUrl = Symbol('GenerateUrl');

export const NavigationMixin = (Base) => {
    return class extends Base {
        [Navigate](pageReference, replace) {
            navigateCalls.push({ pageReference, replace });
        }
        [GenerateUrl]() {
            return Promise.resolve('/generated');
        }
    };
};
NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

/** Test helpers */
export const getNavigateCalls = () => navigateCalls;
export const resetNavigateCalls = () => {
    navigateCalls = [];
};
