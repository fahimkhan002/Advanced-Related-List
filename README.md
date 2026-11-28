# Tekenable Advance Related List

A Salesforce Lightning component for record pages that shows a related list with search, AND/OR filters, whole-list sorting, paging, header buttons with a ▾ menu, screen flows, quick actions and bulk delete. Admins set it up with a point-and-click **Tekenable Related List Builder**, with no code or API names to type.

![Tekenable Advance Related List on an Account page](Advance%20Related%20List/docs/user-guide/images/U01-list-on-record-page.png)

## Install

Version **2.0.0-1** (released, unlocked package, no namespace):

- **Production or Developer Edition:** https://login.salesforce.com/packaging/installPackage.apexp?p0=04tdM000000fjIvQAI
- **Sandbox:** https://test.salesforce.com/packaging/installPackage.apexp?p0=04tdM000000fjIvQAI
- **CLI:** `sf package install --package 04tdM000000fjIvQAI --target-org <alias> --wait 20`

Install it in a sandbox first and test it there before installing in production.

## Documentation

- **[User Guide](Advance%20Related%20List/docs/user-guide/README.md)**: how to use the list and how to set it up, with screenshots.
- **[Project README](Advance%20Related%20List/README.md)**: permissions, list definitions, field types, migration from v1, deployment, UAT and rollback.
- Design records: [ADR-001](Advance%20Related%20List/docs/designs/ADR-001-advanced-related-list-v2.md), [ADR-002](Advance%20Related%20List/docs/designs/ADR-002-related-list-builder.md), [ADR-003](Advance%20Related%20List/docs/designs/ADR-003-remembered-filters-and-list-actions.md).

## What's new in version 2

- Every query and delete runs in user mode, so object permissions, field-level security and sharing always apply.
- Reusable list definitions in Custom Metadata, maintained in the Tekenable Related List Builder.
- Header buttons joined like standard Salesforce actions, with a ▾ menu; you choose the order, including where **New** goes, or hide it.
- Any number of screen flows and quick actions, as header buttons or row menu items.
- Each user's filters and sort are remembered for the next visit.
- Existing v1 App Builder placements keep working.

> **Legacy:** the v1 package links (`04tJ30000008qfj`, `04tJ30000008qfe`) install the old v1 package, not this version.

## License

MIT
