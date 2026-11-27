# Advanced Related List LWC Component

A Salesforce Lightning Web Component for record pages that adds server-enforced search, typed AND/OR filters, whole-list sorting, keyset paging, scoped bulk delete and screen-flow launch to a related list.

**Version 2** is a security and architecture upgrade:

- One trusted Apex boundary (`RelatedListController.getRows` and `deleteRows`), with every query and delete in user mode.
- Reusable, deployable **list definitions** in Custom Metadata, with an example **Account → Contacts** definition included.
- Existing App Builder configuration keeps working through a validated, read-compatible legacy path.
- The v1 endpoints `getRecords`, `deleteRecord`, `updateRecords` and `getUserPermissions` have been removed.

The Salesforce DX project is in [`Advance Related List/`](Advance%20Related%20List/). Start with its [README](Advance%20Related%20List/README.md), which covers setup, permissions, migration from v1, deployment, UAT and rollback. The design rationale is in [ADR-001](Advance%20Related%20List/docs/designs/ADR-001-advanced-related-list-v2.md).

> The package installation links published for v1 (`04tJ30000008qfj`, `04tJ30000008qfe`) install the **v1** package, not this source.

## License

This component is released under the MIT License.
