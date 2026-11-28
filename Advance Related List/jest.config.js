const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        // sfdx-lwc-jest ships no base stub for LightningModal or a recording navigation stub.
        '^lightning/modal$': '<rootDir>/jest-mocks/lightning/modal',
        '^lightning/navigation$': '<rootDir>/jest-mocks/lightning/navigation'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    collectCoverageFrom: ['force-app/**/lwc/**/*.js', '!**/__tests__/**'],
    testPathIgnorePatterns: ['/node_modules/', '<rootDir>/fixtures/']
};
