# Tekenable Advance Related List (v2)

A Lightning Web Component that shows one related list on a record page. It adds search, typed filters with AND/OR, sorting of the whole list, paging, and optional bulk delete and screen-flow launch. All data scope is enforced on the server for the running user.

> **v2 is a security and architecture upgrade of v1.** Existing pages keep working through a read-compatible legacy path. Some actions need an admin-maintained *list definition*; see [Migrating from v1](#migrating-from-v1). The design decision record is [docs/designs/ADR-001-advanced-related-list-v2.md](docs/designs/ADR-001-advanced-related-list-v2.md).

## Install

The package is an unlocked package with no namespace. Version **2.0.0-1** (beta) is ready for **sandboxes, scratch orgs and Developer Edition orgs**:

- Sandbox: https://test.salesforce.com/packaging/installPackage.apexp?p0=04tdM000000fjIvQAI
- Developer Edition / other non-production login: https://login.salesforce.com/packaging/installPackage.apexp?p0=04tdM000000fjIvQAI
- CLI: `sf package install --package 04tdM000000fjIvQAI --target-org <alias> --wait 20`

A beta version can't be installed in production. A released (promoted) version will be added here for production installs.

After installing, assign the permission sets (see [Permissions](#permissions)) and follow the **[User Guide](docs/user-guide/README.md)**, which shows every step with screenshots for end users and admins.

API names stay the same as earlier versions (`Advanced_Related_List__mdt`, `c-advance-related-list`, `Advanced_Related_List_User`), so existing pages and deployments keep working. Only the labels shown in Salesforce changed.

## Contents

- [User Guide (with screenshots)](docs/user-guide/README.md)
- [When to use this instead of the standard component](#when-to-use-this-instead-of-the-standard-component)
- [Quick setup (Account → Contacts)](#quick-setup-account--contacts)
- [Permissions](#permissions)
- [Related List Builder (admin UI)](#tekenable-related-list-builder-admin-ui)
- [List definitions](#list-definitions)
- [Page placement and App Builder properties](#page-placement-and-app-builder-properties)
- [Supported objects and field types](#supported-objects-and-field-types)
- [Flow inputs](#flow-inputs)
- [Behaviour reference](#behaviour-reference)
- [Migrating from v1](#migrating-from-v1)
- [Deployment](#deployment)
- [Sandbox validation, UAT and release-update checks](#sandbox-validation-uat-and-release-update-checks)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)
- [Development and verification](#development-and-verification)

## When to use this instead of the standard component

Start with the standard **Dynamic Related List – Single** component in Lightning App Builder. It covers one related list with admin-chosen fields, sort and filters, plus standard actions. Use this component only when you need one of these:

| Need | Standard component | This component |
|---|---|---|
| One list definition reused on many pages and deployed between sandboxes and production | Configured per page | Custom Metadata definition |
| Users search several fields and build typed AND/OR filters at run time | No | Yes |
| Delete several selected rows at once, with a result for each row | No | Yes, with an extra permission |
| Launch a configured screen flow with the parent record ID | No | Yes |

## Quick setup (Account → Contacts)

1. Install the package (see [Install](#install)) or deploy the source (see [Deployment](#deployment)). It includes the example definition **Account_Contacts**.
2. Assign the **Tekenable Advance Related List User** permission set to the users who will see the list. Optionally also assign **Tekenable Advance Related List Bulk Delete**.
3. Open an Account record and click **Edit Page**.
4. Drag **Tekenable Advance Related List** onto the page and set **List Definition Key** to `Account_Contacts`.
5. Save and activate the page.

The list shows the account's contacts with Name, Title, Email, Phone, Lead Source, Birthdate, Mailing Address and Contact Owner. Users can search Name, Title, Email, Phone and Mailing City (a hidden column). They can filter by Title, Email, Phone, Lead Source, Birthdate and Mailing City, and sort by Name, Title, Email, Birthdate and Contact Owner.

## Permissions

The component grants **no** access to data. Every query and delete runs in user mode (`AccessLevel.USER_MODE`), so object permissions, field-level security and sharing all apply to the running user.

| Permission set | Contents | Assign to |
|---|---|---|
| **Tekenable Advance Related List User** | Apex class access to `RelatedListController` | Everyone who sees the component |
| **Tekenable Advance Related List Bulk Delete** | Custom permission `Advanced_Related_List_Bulk_Delete` | Only users allowed to delete several rows at once |
| **Tekenable Advance Related List Admin** | Custom permission `Advanced_Related_List_Admin`, Tekenable Related List Builder tab and class access | Admins who maintain list definitions (they also need Customize Application) |

Assign business-object permissions separately and as usual: Read on the parent and child objects, field-level security on the fields shown, and Create, Edit or Delete on the child object for those actions. Each action appears only when **both** the definition allows it **and** the user has the matching permission. Hiding a button never grants or removes access. Users can still do whatever their permissions allow through the standard UI.

Fields the user can't read are left out of the list, and a short notice says so. If the user can't read the parent record, the child object or the lookup field, the list shows an access message and returns no rows. The message is the same whether the record doesn't exist or isn't shared with the user.

## Tekenable Related List Builder (admin UI)

Admins create and maintain definitions without editing source or typing API names. The design is in [ADR-002](docs/designs/ADR-002-related-list-builder.md).

1. Assign the **Tekenable Advance Related List Admin** permission set. Saving also needs **Customize Application**.
2. Open **App Launcher → Tekenable Related List Builder**.
3. Click **New related list** (or choose a list on the left) and fill in the steps:
   - **Details:** a label. The API name (List Definition Key) is suggested from it and can't change after saving.
   - **Records to show:** pick the record page object, then the related records. Each option is one lookup, for example *Opportunities (via Account ID)*.
   - **Columns:** **Add column** opens a field picker. Use **›** to follow a lookup, for example *Opportunity Owner › Full Name*. Set the label, choose Show, Search, Filter, Sort or Edit (options the field type can't support are disabled), and reorder or remove columns.
   - **Default order** and **Row actions** (Edit, Delete, Delete selected rows).
   - **Buttons and row menu items:** New plus any number of screen flows and quick actions (up to 10). Use the arrows to set the exact header order (New can go first, last or anywhere), **Show as** to make each header action a button or a **More** menu item, and the bin to remove one (removing New hides the New button). Each action is a list header button (runs for the record page record) or a row menu item (runs for that row). Flows receive the record ID in a text input variable named `recordId`. Quick actions are chosen from those Salesforce reports as available for that object.
4. Click **Check for problems** (the same rules the list enforces), then **Save**. Saving deploys the Custom Metadata and the status changes to *Saved.* after a few seconds.
5. In Lightning App Builder, add **Tekenable Advance Related List** and choose the definition from the **List Definition Key** dropdown. The dropdown lists only active definitions for that page's object.

Removing a column marks it *Removed* (Apex can't delete Custom Metadata records). You can delete it permanently later in Setup → Custom Metadata Types → Tekenable Advance Related List Column.

## Remembered filters

Each user's filters, AND/OR choice and sort for a list are kept in their browser and come back after a page refresh or on another record with the same list. The list shows *Kept for your next visit* while they apply. **Clear all** forgets them. If an admin later changes the list so that saved filters no longer fit, they are cleared automatically with a short notice. To turn this off for a placement, select **Don't Keep Users' Filters and Sort** in App Builder. Saved filters don't move between browsers or devices. Details are in [ADR-003](docs/designs/ADR-003-remembered-filters-and-list-actions.md).

## List definitions

A definition is one **Tekenable Advance Related List** record plus one **Tekenable Advance Related List Column** record (and optional **Action** records) per column. Both are Custom Metadata, so you can deploy them with change sets, the Metadata API or packages, and they keep the same values in every environment.

The **Tekenable Related List Builder** (above) is the recommended way to maintain these records. They can also be edited in **Setup → Custom Metadata Types → Tekenable Advance Related List → Manage Records**.

**Tekenable Advance Related List** (`Advanced_Related_List__mdt`)

| Field | Required | Example | Notes |
|---|---|---|---|
| Label / DeveloperName | yes | `Account_Contacts` | DeveloperName is the **List Definition Key** |
| Active | – | ✔ | Inactive definitions show a configuration error and no rows |
| Parent Object | yes | `Account` | Must match the record page object |
| Child Object | yes | `Contact` | |
| Relationship Field | yes | `AccountId` | Lookup on the child that points to the parent. Use **one definition per lookup**: two lookups to the same parent stay separate lists |
| Default Sort Field / Direction | – | `Name` / Ascending | Blank sorts by record ID |
| Allow Create / Edit / Delete | – | ✔ | Row-level actions use standard Salesforce forms and delete |
| Allow Bulk Delete | – | ☐ | Also needs the Bulk Delete permission set |
| Flow API Name | – | `Contact_Update` | Legacy single flow. Use **Actions** for one or more flows and quick actions; the builder migrates this field automatically |

**Tekenable Advance Related List Column** (`Advanced_Related_List_Column__mdt`)

| Field | Example | Notes |
|---|---|---|
| Definition | `Account_Contacts` | Parent definition |
| Field Path | `Owner.Name` | Child field, or a relationship path with up to 5 hops |
| Column Label | `Contact Owner` | Blank uses the field label in the user's language |
| Order | `80` | Lowest first |
| Visible | ✔ | Clear for search-only or filter-only fields |
| Searchable / Filterable / Sortable | | Only valid for supported field types. An invalid setting is a configuration error that names the field |
| Editable | | Fields shown in the Edit dialog (child fields only). Blank on every column uses the page layout |

The configuration is validated against the running user's schema and permissions on every request. Unknown fields, polymorphic relationship hops (for example `What.Name`), a lookup that doesn't point to the parent, and unsupported capabilities all produce an actionable **configuration error** and no rows.

## Page placement and App Builder properties

Targets are unchanged: Record Page, App Page and Home Page. Rows appear only where the page supplies a record ID, so in practice that means record pages. On app and home pages the component shows a placement message.

| Property | Owner | Notes |
|---|---|---|
| **List Definition Key** (`listDefinition`) | new in v2 | When set, the definition controls records, columns and actions, and the legacy properties are ignored |
| List Title, Records Per Page (1–100), Custom Icon Name, Icon Background Color (hex only), Flow Modal Title | presentation | Apply in both modes |
| Legacy: Child Object, Parent Lookup Field, Fields to Display, Searchable Fields, Column Labels, Sortable Fields, Flow API Name | legacy data properties | Used only when List Definition Key is blank. Names are unchanged from v1 |

The component supports phone and desktop form factors on record pages and app pages. On phones it shows cards with an action menu and a Sort by selector. Bulk selection and column settings are desktop-only.

## Supported objects and field types

Any object the user can read that has a lookup or master-detail field pointing to the parent works. This includes standard and custom objects and several lookups to the same parent.

| Field type | Display | Search | Filter operators | Sort |
|---|---|---|---|---|
| Text, Email, Phone, URL, Text Area | as text, email link, phone link, link | yes | equals, does not equal, contains, does not contain, starts with, ends with, is blank, is not blank | text, email, phone, URL |
| Picklist | translated label | yes | equals, does not equal, is blank, is not blank | – |
| Multi-select picklist | translated labels | – | – | – |
| Number, Currency, Percent | locale-formatted; currency uses the record currency in multi-currency orgs | – | equals, does not equal, less than, greater than, at most, at least, is blank, is not blank | yes |
| Date | locale date | – | as number (on/before/after) | yes |
| Date/Time | locale date and time | – | a **date** that matches the whole day in the user's time zone | yes |
| Checkbox | checkbox | – | equals True/False | – |
| Lookup | related record name, linked | – | – | – |
| Name field (own or related) | linked to the record | yes | as text | as text |
| Address, Geolocation | formatted, single line (child fields only) | – | – | – |
| Rich text | shown as plain text | – | – | – |

Search and text filters treat `%`, `_` and `\` as literal characters. Limits: 25 columns, 20 filter conditions, 100 characters of search text, 100 rows per page, and 100 rows per bulk delete. Totals above 2,000 show as "2,000+".

## Flow inputs

All flow actions (header and row) receive the record they run for in a text input variable named `recordId`: the record page record for header buttons, the row record for row items. Configure flows and quick actions in the Related List Builder (section 6). The legacy single flow below still works.


The flow button launches the configured **screen flow** in a dialog. It shows only to users who can edit the child object, as in v1. The flow receives one input variable:

| Variable | Type | Value |
|---|---|---|
| `recordId` | Text, *Available for input* | ID of the record page's record (the parent) |

The flow runs in its own configured context and with its own access checks. Opening it from this list grants nothing. A flow that performs privileged operations must do its own authorization. When the flow finishes, the list refreshes. Closing the dialog doesn't refresh the list, and a flow error shows a message.

## Behaviour reference

| Behaviour | v1 | v2 | Status |
|---|---|---|---|
| Columns, labels, title, icon | ✔ | ✔ (icon colour must be hex) | retained |
| Name and related-record links, addresses | ✔ | ✔ | retained |
| Search | ✔ (300 ms) | ✔ debounced, out-of-date responses ignored, resets to page 1 | improved |
| Filters with AND/OR | per-row AND/OR (mixing produced invalid queries) | typed controls, one "all / any" choice, active-filter pills, Clear all | intentionally migrated |
| Sorting | current page only | whole list on the server, stable tie-breaker | improved |
| Paging | OFFSET (fails past 2,000 rows) | keyset cursor, Previous/Next, "Page X of Y" | improved |
| Row selection and bulk delete | one request per row, all-or-nothing message | one bounded request, per-row results, failures stay selected | improved, needs a definition |
| Create | standard New with parent defaulted | same | retained |
| Edit | every updateable field in a custom modal | page layout, or the definition's editable fields, in an accessible modal | improved |
| Single delete | custom Apex delete without list context | standard Lightning Data Service delete with confirmation | intentionally migrated |
| Refresh / `refresh()` public method | current page | first page with a fresh total | retained (name), improved |
| Column widths, reset | ✔ (session only) | ✔ (session only) | retained |
| Flow launch | ✔ | ✔ with finish/cancel/error handling | retained |
| Empty, no-match, configuration, access and error states | partial | explicit, with recovery actions | improved |
| Keyboard, focus and screen reader support | partial | labelled controls, live result announcements, focus return after dialogs | improved |
| Phone layout | – | cards | new |

## Migrating from v1

v1's App Builder configuration keeps working after you deploy v2. **Until an admin creates a definition, legacy placements have no bulk delete.** View, New, Edit, single-record Delete, search, filters, sort and Flow still work, and all of them enforce the user's own permissions.

**Removed Apex endpoints.** `getRecords`, `deleteRecord`, `updateRecords` and `getUserPermissions` were removed from `RelatedListController`. If anything else in your org calls them, the deployment fails and names the caller. That failure is the intended signal, not a reason to restore the methods.

### Staged migration

1. **Sandbox, deploy v2.** Existing pages render through the legacy path. Run the UAT below on them.
2. **Create a definition per placement.** Map the old properties as follows:

   | v1 property | Definition field |
   |---|---|
   | Child Object API Name | Child Object |
   | (record page object) | Parent Object |
   | Parent Lookup Field API Name | Relationship Field |
   | Fields to Display (in order) | one Column per field: Field Path, Order 10, 20, … |
   | Column Labels | Column Label on the matching column |
   | Searchable Fields | Searchable on the column. Add a hidden column (Visible off) for fields that were searchable but not displayed |
   | Sortable Fields | Sortable on the column |
   | Flow API Name | Flow API Name |
   | (v1 sorted by CreatedDate descending) | Default Sort Field `CreatedDate`, Direction Descending, to keep the old order |
   | – | Allow Create/Edit/Delete as needed; Allow Bulk Delete only if required |

3. **Edit the page.** Set **List Definition Key** and leave the legacy properties as they are. They are ignored while a key is set, which makes the change reversible.
4. **Assign permission sets**, including Bulk Delete for the users who need it.
5. **Promote.** Deploy the definitions (Custom Metadata records), then the pages, to the next environment.

**Reversible page example.** Before the change, the page has Child Object `Contact`, Parent Lookup Field `AccountId` and Fields to Display `Name,Email,Phone`. After it, the same values remain and List Definition Key is `Account_Contacts`. To revert, clear List Definition Key and the page uses the legacy values again.

## Deployment

Prerequisites: an org on API 67.0 (Summer '26) or later. All orgs on the current GA release (Winter '27, API 68.0) qualify. No managed-package dependency. The v1 package install links in older documentation (`04tJ30000008qfj`, `04tJ30000008qfe`) install the legacy **v1** package; use the links in [Install](#install) for this version.

The production-safe manifest is `manifest/package.xml`. It covers the Apex classes, the three Custom Metadata types and the example records, the custom permissions, three permission sets, the builder tab and page, and the LWC bundles. **Never deploy `fixtures/` to production.** It holds sandbox-only test objects, definitions and tests.

```bash
# 1. Validate in the designated sandbox (no changes are saved)
sf project deploy validate --manifest manifest/package.xml --target-org <sandbox-alias> --test-level RunSpecifiedTests \
  --tests RelatedListControllerTest --tests RelatedListQueryBuilderTest

# 2. Deploy to the sandbox (after approval)
sf project deploy start --manifest manifest/package.xml --target-org <sandbox-alias> --test-level RunSpecifiedTests \
  --tests RelatedListControllerTest --tests RelatedListQueryBuilderTest

# 3. Sandbox-only fixtures: custom-object relationship, two lookups to Account, custom-object Aura response check
sf project deploy start --source-dir fixtures --target-org <sandbox-alias> --test-level RunSpecifiedTests --tests RelatedListFixtureTest

# 4. Assign runtime permissions to the UAT users
sf org assign permset --name Advanced_Related_List_User --target-org <sandbox-alias> --on-behalf-of <uat-user>
```

The deploy order is handled by the metadata API: object types are deployed before records. Deploying v2 removes no data. The only metadata removed is four Apex methods. No custom objects, fields or records are deleted.

## Sandbox validation, UAT and release-update checks

Use a **designated non-production sandbox** and least-privilege UAT users: one reader (Read only), one editor (Read/Edit/Delete) and one bulk deleter (editor plus Bulk Delete). Give each user a permission-set-based profile, not System Administrator.

| # | Check | Expected |
|---|---|---|
| U1 | Apex tests (`RelatedListControllerTest`, `RelatedListQueryBuilderTest`, `RelatedListFixtureTest`) | All pass. Record the run ID, pass count and coverage of each class |
| U2 | Reader opens Account → `Account_Contacts` | Rows load. No Edit, Delete or Bulk Delete. Hidden-field notice when FLS removes a column |
| U3 | Reader opens an Account they can't see (direct URL) | "This record isn't available to you." and no rows |
| U4 | Editor: search `%`, filters (text, picklist, date, Date/Time, number, checkbox), AND vs OR, Clear all, sort each sortable column, page to the end and back | Correct rows, no duplicates or gaps, no-match state with Clear |
| U5 | Bulk deleter: select rows, delete. Repeat with a row locked by a validation rule or sharing | One request. Per-row outcome. Failures stay selected with a reason |
| U6 | **Release update "Remove Non-Public Fields from Custom Object Data in Aura Action Responses"**: in Setup → Release Updates, run U2/U4/U5 on the fixture lists (`ARL_Fixture_*`) and `Account_Contacts` with the update **off**, then use **Test Run** and repeat the same steps with the same users and data. Compare the browser network responses of `RelatedListController.getRows` | Identical rows and keys in both states. v2 returns no SObjects, so no difference is expected |
| U7 | Keyboard only: Tab through toolbar, filters (Escape closes, focus returns to the Filters button), datatable, row menu, Edit/Delete dialogs (focus returns), pagination | Everything reachable, visible focus, announcements in a screen reader |
| U8 | Salesforce mobile app on a real phone: record page with the component | Cards, action menu, Sort by, paging. No horizontal scroll |
| U9 | SLDS and accessibility review in Chrome DevTools/axe | No critical issues |
| U10 | Benchmark: Account with ~20 contacts and an Account with 2,500+ contacts. Record page-load time, `getRows` server time and debug-log SOQL/CPU for first page, page 25, sorted, filtered. Bulk delete 100 rows: 2 SOQL + 1 DML | Recorded in the release notes |

## Rollback

v2 doesn't change data, so rollback is a source and configuration rollback:

1. Redeploy the v1 source from Git commit `32285ffcb527b89748c07fa61ebb9cedbc0f09ec` (the `Advance Related List/force-app` folder) with the same `sf project deploy start` command. This restores the v1 controller methods and the v1 component.
2. Pages using only legacy properties keep working with v1 unchanged. On pages where you set **List Definition Key**, clear it before or right after the rollback. v1 ignores the property, but App Builder may warn about an unknown property until it is cleared.
3. The Custom Metadata types, records, custom permission and permission sets can stay, because v1 doesn't use them. Remove them later with a reviewed destructive change only if needed. Deleting a Custom Metadata type also deletes its records.
4. A sandbox rollback rehearsal is part of the release checklist.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| *List definition "X" was not found* | Wrong key, or records not deployed | Check the DeveloperName under Custom Metadata Types |
| *… is inactive* | Active is unchecked | Activate the definition |
| *… is for Account records, but this page shows Case records* | Definition placed on the wrong object | Use a definition whose Parent Object matches the page |
| *Field "X" was not found on Contact* / *is not a relationship* / *polymorphic* | Bad field path | Fix Field Path, or use a non-polymorphic path |
| *Field "X" cannot be sorted / searched / filtered* | Capability not supported for that type | Clear the flag, or choose another field |
| *Place this component on a record page* | No record ID (app or home page) | Move it to a record page |
| *You don't have access to …* / *This record isn't available to you* | Missing object permission, FLS on the lookup, or sharing | Grant access through a permission set |
| *Some columns are hidden…* | User lacks FLS on those fields | Expected. Grant FLS if the user should see them |
| No Bulk Delete button | Definition disallows it, the user lacks the Bulk Delete permission set or child Delete, legacy mode, or phone | Check each condition |
| *The list changed. Showing the first page.* | Paging cursor no longer matches the query | Automatic. No action needed |

## Development and verification

```bash
npm install          # Node 20+, uses package-lock.json
npm run lint         # ESLint 9 flat config (eslint.config.js)
npm test             # LWC Jest (sfdx-lwc-jest)
npm run test:unit:coverage
sf code-analyzer run --workspace force-app --workspace fixtures --rule-selector Recommended
```

The verification evidence for this change is in [docs/verification/2026-11-24-v2-verification.md](docs/verification/2026-11-24-v2-verification.md).

## License

MIT
