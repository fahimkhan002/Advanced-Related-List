# ADR-001 — Advanced Related List v2: scoped reads, admin definitions, safe writes

Status: Proposed — implemented on branch `feature/modernize-related-list`; a human must set
`Status: Approved` (gate G1) before merge or any deployment.
Date: 2026-11-24 · Baseline: `main` @ `32285ffcb527b89748c07fa61ebb9cedbc0f09ec`

## 1. Baseline audit (source observations, rechecked at the baseline SHA)

| # | Evidence (baseline file:line) | Affected behaviour | Priority | Remediation | Verifying test |
|---|---|---|---|---|---|
| A1 | `RelatedListController.cls:374-431` `buildWhereClause` concatenates client-supplied field names, the `operator` (`when else` → `field + ' ' + operator`) and `logicOperator` into SOQL; `escapeSingleQuotes` does not protect identifiers or operators | Any user with class access can inject SOQL predicates/identifiers through `filters` (PMD ApexSOQLInjection ×3) | Critical | Describe-validated identifiers, fixed operator/join enums, every value bound via `queryWithBinds` | `RelatedListQueryBuilderTest.unknownOperatorIsRejected`, `userValuesNeverAppearInSoqlText`, `likeEscapingIsLiteral`; `RelatedListControllerTest.invalidFieldPathsAreRejected`, `inputBoundsAndUnknownOperatorsAreRejected` |
| A2 | `:123-125` `checkFieldAccess` returns on unknown field; `:100-106` only checks the first relationship segment; `:90-97` any name ending “address” is checked as-is | Unchecked relationship hops/terminal fields; query runs in system mode at API 62 | High | Hop-by-hop path resolution with FLS on every hop and terminal field; `WITH USER_MODE`/`AccessLevel.USER_MODE` backstop | `RelatedListControllerTest.invalidFieldPathsAreRejected`, `polymorphicHopIsRejected`, `hiddenFieldIsOmittedForRestrictedUser` |
| A3 | `:152-200` `getRecords` accepts object/lookup/fields from the browser; no check that `parentLookupField` references the parent's type or that the user can read the parent | Any child object can be listed by any lookup value | High | Parent Id type check, parent read check, lookup `referenceTo` check, user-mode queries | `RelatedListControllerTest.legacyWrongLookupTargetIsConfigError`, `legacyNonLookupFieldIsConfigError`, `definitionOnWrongParentObjectIsConfigError`, `deniedParentGetsAccessErrorWithoutRevealingExistence`, `userWithoutChildAccessGetsAccessError` |
| A4 | `:437-460` count and page query share a string but neither is user-mode; ORDER BY `CreatedDate DESC` only, no tie-breaker; `OFFSET` paging (2,000 row ceiling) | Unstable pages with duplicate timestamps; deep pages fail | Medium | One predicate builder for list and count, `ORDER BY <field> NULLS LAST, Id`, keyset cursor bound to query fingerprint | `RelatedListControllerTest.keysetPagingWithDuplicateSortValuesVisitsEveryRowOnce`, `tamperedOrMismatchedCursorIsStale`, `queryBudgetPerPage` |
| A5 | `:246-291` `updateRecords(List<SObject>, objectName)` checks only `objectName`, not the SObject types sent; logs payloads (`:250`); `Database.update(records,false)` in system mode | Arbitrary-object, arbitrary-field update route; UI does **not** import it (only `getRecords`, `getUserPermissions`, `deleteRecord` at `advanceRelatedList.js:8-10`) | Critical | **Retired** (removed). Single-record edit uses LDS `lightning-record-form` | Compile-time: method no longer exists (any remaining caller fails deployment); `grep` evidence in README §Verification |
| A6 | `:216-239` `deleteRecord(recordId, objectName)`: no parent/list context; `delete` in system mode | Any record the user can see can be deleted through the list's endpoint, regardless of list | High | **Retired**. Single delete → LDS `deleteRecord` (platform enforced). Bulk delete → new `deleteRows` scoped to definition + parent | `RelatedListControllerTest.bulkDeleteMixedOutcomeIsTruthfulAndScoped`, `bulkDeleteRequiresCustomPermissionDefinitionAndBounds`; fixture `bulkDeleteRespectsTheSelectedLookup` |
| A7 | `advanceRelatedList.js:577-606` bulk delete fans out N `deleteRecord` calls via `Promise.all`; first rejection reports total failure though others succeeded | Untruthful outcome, N round trips, N DML | High | One bounded request, `Database.delete(rows,false,USER_MODE)`, per-row results, failures stay selected | Jest `bulk delete › sends one bounded request and reports a mixed outcome truthfully`; Apex `bulkDeleteMixedOutcomeIsTruthfulAndScoped` |
| A8 | `getUserPermissions` (`:293-305`) — object CRUD only | Used to show buttons; redundant with response context | Low | **Retired**; capabilities returned in `getRows` context | Jest `actions › hides actions the user is not allowed to use` |
| A9 | `advanceRelatedList.js:324-376` `handleSort` sorts only the current page client-side | Sorting is misleading on multi-page lists | High (UX) | Server-side sort over the whole scoped list | Jest `sorts the whole list on the server from page 1`; Apex `sortAppliesToWholeListNotCurrentPage` |
| A10 | `RelatedListWrapper.records : List<SObject>` (`:13-21`) | Raw SObject in Aura action response; LWC reads `record[field]`, `record[rel][field]`, `rel.Id`, `Name`, `<prefix>Street/City/State/PostalCode/Country`, `CurrencyIsoCode` (`js:959-1065`, `1220-1240`) | Medium | Narrow DTO (`rows: List<Map<String,Object>>` keyed by column key) — no SObject in Aura responses | Apex `definitionReadReturnsDeclaredDtoOnly`, `absentOptionalKeysAndLegitimateFalsyValues`; fixture `customParentRelationshipAndTypedValues`; Jest `rendering › *` |
| A11 | `__tests__/advanceRelatedList.test.js:23` `expect(1).toBe(1)`; Apex tests assert `!= null` / `System.assert(true)` (`Test.cls:250,267,510,541,563,597`) | No behavioural evidence | High | Behavioural Jest + permission-aware Apex tests | Apex suites (2 + fixture) and Jest suites (6) in this change |
| A12 | `package.json` eslint 9 + `@lwc/eslint-plugin-lwc@1` (peer eslint ≤8), legacy `.eslintrc.json` | `npm install` ERESOLVE; lint cannot run | Medium (tooling) | Aligned devDependencies, flat `eslint.config.js` | `npm install`, `npm run lint` |
| A13 | `advanceRelatedList.js` many `console.log` of records; `html:136` `javascript:void(0)` link; custom modals without focus management | Data in browser console; a11y gaps | Medium | Removed logging; `lightning-button-menu`, `LightningConfirm`, `LightningModal` | Jest `filters › closes the panel on cancel and returns focus`, `deletes one row … restores focus to the heading` |
| A14 | Filter join: per-row `logicOperator` concatenated without parentheses (`:425-429`) | Mixed AND/OR is ambiguous/invalid SOQL | Medium | Single list-level join: “All conditions” (AND) / “Any condition” (OR) | `RelatedListQueryBuilderTest.orJoinIsParenthesised`; Apex `typedFiltersWithAndOr` |

### Aura transport vs non-public-field release update

The LWC calls Apex through the Aura action transport (`@salesforce/apex/...` imports); there are
no Aura framework source files in the repo. The baseline returned `List<SObject>` inside
`RelatedListWrapper`, so its responses were in scope of “Remove Non-Public Fields from Custom
Object Data in Aura Action Responses”. Dependency analysis of the baseline LWC:

| Key read by baseline LWC | Kind | Dependency on non-public fields |
|---|---|---|
| `Id`, configured field names, `rel.Id`, `rel.<field>` | public API fields | Direct dependency on **public** fields only — not removed |
| `Name` (`nameUrl`) | public | none |
| `<Prefix>Street…Country` | public address components | none |
| `CurrencyIsoCode` | public (multi-currency orgs) | indirect assumption: falls back to user currency when absent |
| any undeclared/system key | — | **no evidence** of use |

Conclusion: no evidence the baseline breaks, but v2 removes the exposure entirely by returning
a declared DTO. Runtime confirmation across update states is **pending** (UAT §U6 in README).

## 2. Decision: when the standard component is enough

Use **Dynamic Related List – Single** (standard Lightning App Builder component) when the
requirement is a single related list with admin-chosen fields, sort and simple filters on a
record page, using standard actions. Choose this custom component only for the verified gaps:

1. one **reusable, deployable list definition** shared by many pages and promoted between
   environments (Custom Metadata);
2. user-driven **typed filtering with AND/OR and multi-field search** at runtime;
3. **scoped bulk delete** with per-row outcomes;
4. a configured **screen Flow** launched with the parent `recordId`.

(Exact standard-component limits — filter count, field count, mobile behaviour — must be
rechecked on the help page below; automated retrieval returned only a script shell.)

## 3. Configuration ownership and precedence

| Concern | Owner | Mechanism |
|---|---|---|
| Placement, title, icon, colour, page size, flow modal title | page author | App Builder properties (unchanged names) |
| Parent/child/lookup, ordered columns, default sort, searchable/filterable/sortable/editable fields, allowed actions, Flow | admin, deployable | `Advanced_Related_List__mdt` + `Advanced_Related_List_Column__mdt`, selected by App Builder property `listDefinition` |
| Bulk delete privilege | security admin | Custom permission `Advanced_Related_List_Bulk_Delete` via permission set |
| Class access | security admin | Permission set `Advanced_Related_List_User` |

Precedence: a **valid, active** selected definition owns data scope, columns and actions; the
legacy data properties are ignored. An unknown/inactive/invalid definition yields a
configuration error and **zero rows** (no fallback). With no key the **legacy read path** is
used: the same server validation is applied to the browser-supplied properties (they are
treated as untrusted input), and only platform-enforced single-record actions are offered.
**Bulk delete is unavailable until an admin migrates to a definition.** Saved views
(custom object) are deferred: no concrete private, cross-device requirement was identified.

Schema choice: object/field references are Text validated against describe at run time rather
than `EntityDefinition`/`FieldDefinition` metadata relationships, because columns need
relationship paths (`Account.Owner.Name`) and compound fields that `FieldDefinition` cannot
express, and a per-column entity relationship would add a second required field without adding
run-time safety (the running user's describe is checked on every call regardless). The column →
definition link is a metadata relationship (`Definition__c`) for referential integrity in Setup.

## 4. Read path

| Option | Fit | Decision |
|---|---|---|
| `getRelatedListInfo/Records` (UI API) | Platform FLS/sharing, pageToken paging; tied to a child relationship's related list; filter/search semantics and object coverage must be rechecked | Not chosen: cannot share the server-side scope with bulk delete; multi-field LIKE search and total count not established |
| `lightning/graphql` | Cursor paging (`first/after`), filters, `orderBy`; UI-API-supported objects only | Not chosen as primary; candidate for a later read-only variant |
| **Scoped Apex** (`RelatedListController.getRows`) | One trusted boundary for read, count and delete scope | **Chosen** — single primary path, no fallback |

Single-record operations use standard platform paths: `NavigationMixin` (view/new),
`lightning-record-form` (edit), `deleteRecord` from `lightning/uiRecordApi` (single delete).

## 5. Security and data contract (summary)

* `public with sharing`; every query `Database.queryWithBinds/countQueryWithBinds(...,
  AccessLevel.USER_MODE)`; delete `Database.delete(rows, false, AccessLevel.USER_MODE)`.
  Definition metadata is read `WITH SYSTEM_MODE` (configuration, not business data).
* Parent Id must parse, be of the definition's parent type, and be readable by the user.
* Lookup must be a reference field on the child whose `referenceTo` contains the parent type,
  readable and filterable. Two lookups to the same parent remain distinct because the lookup
  field is part of the definition.
* Field paths: ≤5 hops, each hop a non-polymorphic, readable relationship; terminal readable.
  Fields used in predicates/sort must be filterable/sortable. Inaccessible *display* fields are
  omitted (warning count only); inaccessible scope fields fail closed.
* Typed operator map; values parsed by `Schema.DisplayType`; `%`, `_` and `\` are literal.
* Bounds: page size 1–100, ≤25 columns, ≤20 filters, search ≤100 chars, delete ≤100 Ids.
* Ordering: `<sort> ASC|DESC NULLS LAST, Id ASC`; keyset cursor bound to a SHA-256 fingerprint
  of definition/parent/search/filters/sort; mismatch → client resets to page 1.
  Count computed on first page only, capped at 2,000 (“2,000+”).
* Response: declared DTO only (columns, row Id, cell values/labels/link Ids, paging, context).
* Errors: categorised (`CONFIG`, `ACCESS`, `INPUT`, `ERROR`); no stack traces, no payload logs;
  parent “not found” and “no access” are indistinguishable.

## 6. API version

Winter '27 (API 68.0) is the current GA release (production upgrades completed Oct 2026).
API 67.0 (Summer '26) makes Apex run in **user mode by default** and removes
`WITH SECURITY_ENFORCED`. Chosen version: **67.0** for project, classes and bundles — the
minimum that gives user-mode-by-default as defence in depth, available on every org on the
current GA release. All database operations still declare an explicit access mode, so
behaviour does not depend on the file version. 68.0 was not chosen because its Apex
version-specific changes could not be verified from official pages in this session.

## 7. Sources (recheck before approval)

Automated retrieval of developer.salesforce.com returned HTTP 403 and help.salesforce.com
returned only a script shell during this session; facts above marked “recheck” are from search
excerpts of these official pages:

* Aura action response update — help.salesforce.com `release-notes.rn_lc_rus_remove_nonpublic_fields_ru.htm` (release 264); Release Updates index `release-notes.rn_ru.htm`
* Apex access mode / API 67 — developer.salesforce.com `apexcode.meta/apexcode/apex_classes_enforce_usermode.htm`; LWC `apex-security.html`
* Dynamic SOQL & binds — `apex-dev/apex-dynamic-soql.html`
* Dynamic Related List – Single — help `platform.lightning_page_components.htm`
* `getRelatedListInfo` / `getRelatedListRecords` / GraphQL pagination — LWC developer guide pages
* Custom metadata lifecycle — Trailhead `custom_metadata_types_dec/cmt_overview` (fetched: records deployable via packages, Metadata API, change sets; supports metadata relationships)
* Winter '27 developer guide — developer.salesforce.com/blogs/2026/10/developers-guide-to-the-winter-27-release
* `lightning-datatable`; Salesforce Code Analyzer v5 guide
