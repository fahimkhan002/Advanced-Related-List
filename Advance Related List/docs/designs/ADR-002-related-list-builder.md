# ADR-002 — Related List Builder (admin UI)

Status: Proposed — implemented on branch `feature/modernize-related-list`; a human must set
`Status: Approved` (gate G1) before merge or deployment beyond the disposable scratch org.
Date: 2026-11-26 · Extends ADR-001.

## Problem

The scratch-org demo showed that v2 definitions could only be maintained with typed API names: object
names, the lookup field, field paths, the default sort field, the Flow name, and the List Definition Key
in App Builder. Mistakes surfaced only at run time. Columns appeared as one flat list across all
definitions.

## Decision

| Need | Mechanism |
|---|---|
| Edit definitions without API names | LWC `arlListBuilder` on a Lightning app page plus tab **Related List Builder** (App Launcher) |
| Choose the relationship | The parent object's child relationships (`DescribeSObjectResult.getChildRelationships`), each shown as one child object + one lookup, so two lookups to the same parent stay distinct |
| Choose fields and paths | `arlFieldPicker`: readable fields with what each supports. Single-target lookups can be followed up to 5 hops, the runtime limit |
| Prevent invalid settings | Capability checkboxes are disabled for unsupported types. The server validates with the **same** `RelatedListSchemaService` rules the list runs (`resolveForParentType`, `supportsSearch/Filter/Sort`) |
| Save | Apex Metadata API (`Metadata.Operations.enqueueDeployment`). Custom Metadata can't be written with DML |
| Remove columns | `Advanced_Related_List_Column__mdt.Removed__c` (default false). The Metadata API can't delete records, so the loader ignores removed columns and admins can delete them permanently in Setup |
| Know when a save has landed | A SHA-256 signature of the normalised definition, returned on save and polled with `getSignature`; times out after about 90 seconds with guidance to check Deployment Status |
| Pick the definition on a page | `RelatedListDefinitionPicklist` (`VisualEditor.DynamicPickList`) as the `datasource` of **List Definition Key**, showing active definitions for the page's object |

## Security

* Every builder endpoint except `getAccess` requires the custom permission `Advanced_Related_List_Admin`
  (permission set **Advanced Related List Admin**) **and** Customize Application.
* Definitions are read `WITH SYSTEM_MODE` (configuration). Schema browsing uses describe for the
  running admin, and the EntityDefinition and FlowDefinitionView queries run `WITH USER_MODE`.
* All written values are validated on the server. Column DeveloperNames from the browser are reused only
  when they already belong to the definition being saved; otherwise the server generates them.
* The builder writes configuration only. Runtime data access is unchanged: user mode everywhere.

## Limitations

* Saves are asynchronous, usually a few seconds. If two admins save the same definition at the same
  time, the last save wins.
* Removed columns stay as records with `Removed__c = true` until deleted in Setup.
* API names of saved definitions can't be changed, because pages refer to them.
