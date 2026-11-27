'use strict';

const globals = require('globals');
const lwcRecommended = require('@salesforce/eslint-config-lwc/recommended');

module.exports = [
    {
        ignores: ['**/node_modules/**', '**/.sfdx/**', '**/.sf/**', 'coverage/**']
    },
    ...lwcRecommended.map((config) => ({ ...config, files: ['**/lwc/**/*.js', 'jest-mocks/**/*.js'] })),
    {
        files: ['**/lwc/**/*.test.js', 'jest-mocks/**/*.js'],
        rules: {
            '@lwc/lwc/no-unexpected-wire-adapter-usages': 'off'
        },
        languageOptions: {
            globals: { ...globals.node, ...globals.jest }
        }
    }
];
