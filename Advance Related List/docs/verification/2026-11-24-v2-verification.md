# Verification evidence: Advanced Related List v2

Date: 2026-11-24 · Branch: `feature/modernize-related-list` · Baseline: `32285ffcb527b89748c07fa61ebb9cedbc0f09ec`
No Salesforce org was used. Everything marked **pending (org)** was not run.

## Environment

| Tool | Version |
|---|---|
| Node / npm | v26.12.1 / 11.20.0 |
| Salesforce CLI | @salesforce/cli 2.155.8 |
| Salesforce Code Analyzer | 5.16.0 (engines that ran: pmd, eslint, cpd, regex, retire-js; flow engine not selected, as there is no flow metadata) |
| ESLint | 9.39.5 (flat config, @salesforce/eslint-config-lwc 4.1.2, @lwc/eslint-plugin-lwc 3.5.0) |
| LWC Jest | @salesforce/sfdx-lwc-jest 7.9.0 (Jest 29.7.0) |

## Baseline (before)

| Check | Command | Result | Classification |
|---|---|---|---|
| Install | `npm install` | **ERESOLVE**: eslint ^9 vs @lwc/eslint-plugin-lwc 1.x (peer eslint ≤8); no lockfile | tooling failure |
| Jest | `npx sfdx-lwc-jest` (after `--legacy-peer-deps`) | 1/1 passed: the single test asserts `expect(1).toBe(1)` | no product coverage |
| Lint | `npx eslint …` | cannot run: ESLint 9 ignores `.eslintrc.json` | tooling failure |
| Code Analyzer | `sf code-analyzer run --workspace force-app --rule-selector Recommended` | 189 violations: **12 High** (3 PMD ApexSOQLInjection, 2 EagerlyLoadedDescribeSObjectResult, 7 ESLint correctness) | product findings |

## After

| Check | Command | Exit | Result |
|---|---|---|---|
| Install | `npm install` | 0 | 746 packages, strict peer resolution, `package-lock.json` committed |
| Lint | `npm run lint` | 0 | 0 problems |
| Jest | `npm test` | 0 | **6 suites, 59 tests passed** |
| Jest coverage | `npm run test:unit:coverage` | 0 | statements 94.35%, branches 80.95%, functions 94.59%, lines 94.17% |
| Metadata shape | `sf project convert source --source-dir force-app` / `fixtures` / `--manifest manifest/package.xml` | 0 | converted without errors |
| Code Analyzer | `sf code-analyzer run --workspace force-app --workspace fixtures --rule-selector Recommended` | 0 | 132 violations: **0 Critical, 0 High**, 57 Moderate, 75 Low |
| Apex tests | `RelatedListControllerTest` (27 methods), `RelatedListQueryBuilderTest` (13), `RelatedListFixtureTest` (4) | – | **pending (org)**: no org authorised; Apex has been parsed by PMD but **not compiled** |

Remaining Moderate/Low findings, by rule: ApexUnitTestClassShouldHaveRunAs (39), ApexDoc (33), CyclomaticComplexity (20), CognitiveComplexity (10), AvoidBooleanMethodParameters (6, test builders), ExcessiveParameterList (6, test builders), `@lwc/lwc-platform/no-inline-disable` (1: debounce `setTimeout`, required by `@lwc/lwc/no-async-operation`), NcssCount (3), AvoidHardcodingId (3, synthetic IDs in tests), TooManyFields (2, DTOs), FieldDeclarationsShouldBeAtStart (2), slds no-hardcoded-values (3). None is a security or correctness rule. `ApexUnitTestClassShouldHaveRunAs` is inapplicable to pure-logic tests; the permission tests use `System.runAs` with explicit permission sets.

## Security findings: before → after

| Finding (baseline evidence) | After |
|---|---|
| SOQL injection through filter operator, join and identifiers (`RelatedListController.cls:374-431`) | Identifiers come only from describe and are hop-validated; fixed operator and join maps; all values bound (`queryWithBinds`). PMD ApexSOQLInjection: 3 → 0 |
| Unknown or relationship fields skipped by FLS checks (`:100-125`) | Every hop and terminal checked; inaccessible display fields omitted; inaccessible scope fields fail closed; `USER_MODE` as backstop |
| No parent type or parent access check; lookup not verified (`:152-200`) | Parent ID type, parent readability (user mode), lookup `referenceTo` all checked on every call |
| `updateRecords` arbitrary SObject update, payload logging (`:246-291`) | Removed; edit goes through LDS |
| `deleteRecord` with no list scope (`:216-239`) | Removed; single delete through LDS; bulk delete scoped to definition, parent and lookup, custom permission, user-mode DML |
| System-mode queries at API 62 | Explicit `AccessLevel.USER_MODE` on every data operation; classes at API 67.0 (user mode by default) |
| Raw `List<SObject>` in Aura responses | Declared DTO only (`Map<String,Object>` rows with declared keys) |
| `console.log` of records; `javascript:void(0)` link; unsanitised style | Removed; `lightning-button-menu`; hex-only colour |

## Benchmarks

Query and DML budgets are asserted by Apex tests (**pending (org)** until run):

| Operation | v1 | v2 (asserted) |
|---|---|---|
| First page | 1 Apex call + permissions call + objectInfo wire; 2 SOQL (count, page); no parent check | 1 Apex call; 3 SOQL (parent check, count `LIMIT 2001`, page) (`queryBudgetPerPage`) |
| Later page | 2 SOQL, `OFFSET` (fails past 2,000) | 2 SOQL (parent check, keyset page), constant cost at any depth |
| Bulk delete of N rows | N Apex calls, N SOQL, N DML statements | 1 Apex call, 2 SOQL, **1 DML** for up to 100 rows (`bulkDeleteMixedOutcomeIsTruthfulAndScoped`), then 1 reload call |
| Large list (2,005 rows) | count uncapped, OFFSET limit | count capped at 2,000 ("2,000+"), 100-row page (`largeListCountIsCappedAndDeepPageIsCheap`) |
| Round trips per search, filter or sort change | 1 (+ none) | 1; earlier responses discarded |

Timing (ms), CPU and heap for a normal list (~20 rows) and a large list (2,500+ rows): **pending (org)**, see README UAT U10.

## Pending (org) checks

1. Deploy validation and Apex test run in the designated sandbox (compiles the Apex for the first time).
2. Custom Metadata SOQL with `Definition__r.DeveloperName` and `WITH SYSTEM_MODE` (`shippedExampleDefinitionLoadsFromCustomMetadata`).
3. LIKE escaping of `%` and `_` in bind values (`searchIsScopedToParentAndTreatsWildcardsLiterally`).
4. Keyset paging with text sort keys and duplicates under the org collation (`keysetPagingWithDuplicateSortValuesVisitsEveryRowOnce`), plus the U4 manual check with accented and mixed-case values.
5. Permission fixtures: Minimum Access profile, `FieldPermissions` on `Contact.AccountId`/`Case.ContactId`, Case-only permission set (`deniedParentGetsAccessErrorWithoutRevealingExistence`).
6. DML-level partial failure (validation rule or locked row) for bulk delete: UAT U5.
7. Release update comparison across update states: UAT U6.
8. Keyboard, screen reader, SLDS and real-phone checks: UAT U7–U9.
9. Benchmarks: UAT U10.
10. Recheck of official documentation that could not be retrieved automatically in this session (ADR-001 §7).
