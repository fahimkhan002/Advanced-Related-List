# Scratch-org demo: Account → Opportunities (2026-11-25)

Disposable scratch org (alias `arl-v2-demo`), expires **2026-12-01**. Contains synthetic data only. No credentials or session URLs are stored in this folder.

## What was configured, and how

| Item | Surface used in the demo | How an admin does it |
|---|---|---|
| `Account_Opportunities` definition (Parent `Account`, Child `Opportunity`, Relationship `AccountId`, default sort `CloseDate` ascending, Create/Edit/Delete on, Bulk Delete off) | Metadata: `demo/main/default/customMetadata/Advanced_Related_List.Account_Opportunities.md-meta.xml` | Setup → Custom Metadata Types → Advanced Related List → Manage Records → New (screens A1, A6) |
| 4 columns: Opportunity Name (search, sort), Stage (filter), Amount (filter, sort), Close Date (filter, sort) | Metadata: `demo/.../Advanced_Related_List_Column.AO_*.md-meta.xml` | Setup → Custom Metadata Types → Advanced Related List Column → Manage Records → New. Order sets position (A2–A5) |
| Account record page with the component, List Definition Key `Account_Opportunities`, Records Per Page 5 | Metadata: `demo/main/default/flexipages/ARL_Account_Record_Page.flexipage-meta.xml` | Lightning App Builder (screen B) |
| Page activation (org default, desktop and phone) | Metadata: `demo/main/default/objects/Account/Account.object-meta.xml` (actionOverrides) | App Builder → Activation… → Org Default |
| Permission set `Advanced_Related_List_User` for the demo user | CLI `sf org assign permset` | Setup → Users → Permission Set Assignments |
| Demo data (2 accounts; 14 + 3 opportunities) | `scripts/apex/seed-demo.apex` (repeatable; a second run creates nothing) | – |

## Screenshots (`screenshots/`)

- **A, admin configuration:** A1 definition record · A6 definition edit screen · A2 all column records · A3/A4 column records · A5 column edit screen
- **B, Lightning App Builder:** component selected, List Definition Key and Records Per Page visible
- **C, end user:** C1 default (14 rows, page 1 of 3) · C2 search "Renewal" (3) · C3a/C3b filter Stage = Value Proposition (2, with pill) · C4/C5 sort Amount descending, pages 1 and 2 · C6 Contoso shows only its own 3

## Gaps found for admins

1. **Missing page layouts (fixed in `force-app/main/default/layouts/`).** Without them, Setup showed only the required fields. Active, sort, actions, Flow and every column capability were invisible and couldn't be edited.
2. API names are typed by hand: Parent Object, Child Object, Relationship Field, Field Path, Default Sort Field, Flow API Name, and the List Definition Key in App Builder. Typing mistakes appear only at run time as a configuration error on the record page.
3. There is no column list on the definition page. Columns are a flat list across all definitions (A2); reordering means editing each column's Order.
4. Search, filter and sort support depends on the field type, but nothing warns about this until run time.
5. Records Per Page and Title live on the App Builder placement, not in the definition.

Gaps 2–4 are closed by the Related List Builder below. Gap 5 remains by design: presentation belongs to the page.

## Related List Builder demo (2026-11-26)

The list **Account Big Deals** was created and configured entirely in the builder UI, with no API names typed. Screenshots are in `screenshots/builder/`:

| Step | Screenshot | What it shows |
|---|---|---|
| D1 | `D1-builder-definitions.png` | App Launcher → Related List Builder: every definition with its relationship and column count |
| D2 | `D2-builder-Account_Opportunities.png` | An existing definition: the relationship shown as "Opportunities (via Account ID)", columns and capabilities |
| D3 | `D3-builder-field-picker-drilled-into-Owner.png` | Field picker following Opportunity Owner › Full Name |
| D4 | `D4-builder-new-list-configured.png` | Columns with only supported capabilities enabled (Stage can't sort; lookup fields can't be edited), a custom label "Deal Owner", default sort Amount descending, and "No problems found" |
| D5a/D5b | `D5a-builder-deploying.png`, `D5b-builder-saved.png` | Save, then "Deploying…", then "Saved." after about 5 seconds |
| D6 | `D6-app-builder-definition-dropdown.png` | App Builder List Definition Key is now a dropdown of active Account definitions |
| D6b | `D6b-app-builder-saved-with-new-definition.png` | The definition chosen from the dropdown and the page saved through App Builder. The page was then restored to the documented demo layout from `demo/` |
| D7/D8 | `D7-…png`, `D8-record-page-Big-Deals-built-in-builder.png` | The Account record page showing the builder-made list: Amount descending by default and the drilled "Deal Owner" column |

Deployed result (queried): `Account_Big_Deals` = Account → Opportunity via `AccountId`, default sort `Amount` descending, with 5 columns (Name searchable; StageName filterable; Amount filterable and sortable; CloseDate sortable; Owner.Name labelled "Deal Owner").

A column `Account_Opportunit_Account_Phone` (Account.Phone) appeared on `Account_Opportunities` during the demo. It wasn't created by the demo scripts and was left unchanged.

## Remembered filters, multiple flows and quick actions (2026-11-26)

Configured entirely in the Related List Builder on **Account Big Deals**. Screenshots are in `screenshots/actions/`.

| Step | Screenshot | Verified in the scratch org |
|---|---|---|
| E1/E2 | `E1-builder-five-actions.png` | Six actions: the existing `Create_Case` flow (migrated from the legacy Flow field) plus two header flows, a header quick action (New Task), a row flow and a row quick action (Log a Call). Checked as "No problems found" and saved |
| E3 | `E3-record-header-buttons-and-more-menu.png` | Header shows *Create a Case* and *Account review*; **More** holds *Forecast note* and *New task* |
| E4 | `E4-header-flow-runs-for-parent.png` | The header flow received the Account ID `001iA0000017IioQAE`. Finish showed "Account review finished." and refreshed the list |
| E5 | `E5-header-quick-action-New-Task.png` | The New Task quick action opened in Salesforce's dialog with *Related To = ARL Demo - Northwind Traders* |
| E6/E7 | `E6-row-menu-…png`, `E7-row-flow-…png` | Row menu: View, Edit, Delete, *Deal check*, *Log a call*. The row flow received the Opportunity ID `006iA000000Zcs7QAC` |
| E8/E9 | `E8-filter-applied.png`, `E9-filter-still-applied-after-page-refresh.png` | Stage = Value Proposition (2 rows) is still applied after a real page reload, showing "Kept for your next visit" |

`Create_Case` (a flow set on the definition's legacy Flow field during testing) was kept and migrated into an action record when the builder saved, and it now shows as *Create a Case*.

## Header control and builder fixes (2026-11-27)

Screenshots are in `screenshots/ui-fixes/`.

| Screenshot | Verified in the scratch org |
|---|---|
| `F2-last-row-dropdown-not-clipped.png` | The last action row's Type dropdown opens fully (all 3 options visible) |
| `F3-builder-New-first-and-show-as.png` | New moved to row 1. Show as set to Button or More menu per action. "No problems found", then Saved |
| `F4-record-header-separate-buttons.png` | Header in the configured order, as separate buttons: New, Account review, Forecast note |
| `F5-record-header-more-menu.png` | More holds Create a Case and New task, as configured |

| `G1-page-standard-and-list-actions.png`, `G2-list-actions-joined-with-overflow-open.png` | List actions joined like the standard record actions (New | Account review | Forecast note | ▾); the ▾ menu holds Create a Case and New task. Measured with no gaps between the buttons |
