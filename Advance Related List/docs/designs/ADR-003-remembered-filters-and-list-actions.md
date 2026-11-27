# ADR-003 — Remembered filters, multiple flows and quick actions

Status: Proposed — implemented on branch `feature/modernize-related-list`; a human must set
`Status: Approved` (gate G1) before merge or deployment beyond the disposable scratch org.
Date: 2026-11-26 · Extends ADR-001 and ADR-002.

## Requests

1. Filters disappeared when the page was refreshed.
2. Admins need any number of flow buttons, not one.
3. LinkedIn request (Chris Rouse): "Does it have the ability to add custom quick action buttons to the related list?"

## Decisions

### Remembered filters and sort

* Stored **per user and per list** (definition key, or the legacy configuration), not per record. A filter
  such as *Stage = Prospecting* follows the user from account to account. Stored in the browser's
  `localStorage` under `arl:v1:<userId>:<list>`, holding filters, AND/OR and sort. Search text is not kept.
* **On by default.** The App Builder property **Don't Keep Users' Filters and Sort** (`disableSavedFilters`)
  turns it off for a placement. Clear all forgets the saved state.
* **Self-healing.** The server validates restored state like any other request. If it is rejected (for
  example an admin removed a filterable column), it is forgotten, the list reloads unfiltered and shows a
  short notice. Corrupt data is ignored.
* **Why not a custom object:** ADR-001 deferred server-side saved views until there is a cross-device need.
  Browser storage meets "survives refresh" with no new data, sharing model or cleanup. Limitation: state
  doesn't follow the user to another browser or device. Named, shareable views across devices would be the
  next step (a private custom object) if needed.

### Actions: any number of flows and quick actions

* New child Custom Metadata type `Advanced_Related_List_Action__mdt`: Definition, Action Type
  (`Flow` | `Quick_Action`), Target, Label, Placement (`List` | `Row`), Order, Removed. Up to 10 per list.
* **List** placement is a header button that runs for the record page's record. **Row** placement is an item
  in each row's menu that runs for that row's record. Flows receive the ID in the text input `recordId`.
  Quick actions open in Salesforce's own dialog (`standard__quickAction`) with that record as context. Up to
  two header actions show as buttons; the rest go under **More**.
* Quick actions are listed and validated with `QuickAction.describeAvailableQuickActions` for the context
  object: the parent for header buttons, the child for row items. Feed publisher types (`Post`) are
  excluded. At run time a quick action that isn't available to the user is not shown.
* Flows without a custom label show the flow's label (one `FlowDefinitionView` query, `WITH USER_MODE`,
  only when needed).
* After a flow finishes, the list refreshes. After a quick action, the list refreshes through
  `lightning/refresh` (`registerRefreshHandler`), which also refreshes it when anything else refreshes the
  record page.

### Compatibility

* The single legacy Flow (`Flow_API_Name__c`, or App Builder **Flow API Name** on legacy pages) still works.
  It becomes a header action labelled with the page's **Flow Modal Title**, and keeps the v1 rule (only
  users who can edit the child object see it).
* The builder shows a legacy Flow as action 1. Saving moves it into an action record and clears
  `Flow_API_Name__c`. Nothing is lost, and the button keeps working before and after.
* `ListContext.flowApiName` is replaced by `ListContext.actions`. The page title for the legacy flow is
  unchanged.

## Security

* Actions are configuration and grant nothing. Flow and quick action access is enforced by Salesforce when
  they start. A flow that performs privileged work must check access itself.
* Remembered state contains only column keys, operators, values and sort, and is re-validated on every
  request. It is stored per user ID in that user's browser profile.

## Addendum (2026-11-27): full control of the header

* **New is an ordered action.** Action Type gains `Standard` (Target `New`, list header only). Its row can be moved
  anywhere, relabelled, shown as a button or in More, or removed (no New button). `Allow_Create__c` mirrors whether
  the row exists. Lists saved before this change keep New at the end (an automatic row the builder shows and saves).
  New is shown only to users who can create the child object.
* **Show as** (`Display__c`: Button | Menu | blank). Each header action is a button or a More-menu item as chosen.
  Blank keeps the previous automatic rule (the first two are buttons). Row items have no Show as.
* **Header buttons match the standard record actions:** one joined button group in the configured order, with the
  overflow as a ▾ icon menu ("More actions") at the end of the same group. Refresh and settings stay separate icons.
* **Builder dropdowns are never clipped.** The actions table is no longer inside a horizontal-scroll container, and
  its comboboxes open upward when there is no room below.
