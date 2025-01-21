# Advanced Related List LWC Component

A flexible Lightning Web Component that provides an enhanced related list experience in Salesforce with features like pagination, search, sorting, bulk actions, and more.

## Installation

### Option 1: Package Installation (Recommended)
1. Install the package in production using this URL:
   ```
   https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ30000008qfZ
   ```
   and for sandbox:
   ```
   https://test.salesforce.com/packaging/installPackage.apexp?p0=04tJ30000008qfZ
   ```
2. Choose the appropriate security level:
   - Install for Admins Only
   - Install for All Users
   - Install for Specific Profiles

### Option 2: Manual Deployment
1. Deploy the following files to your org:
   - `RelatedListController.cls`
   - `RelatedListControllerTest.cls`
   - `advancedRelatedList.js`
   - `advancedRelatedList.html`
   - `advancedRelatedList.css`
   - `advancedRelatedList.js-meta.xml`

## Features

- ✨ Pagination with configurable page size
- 🔍 Real-time search across configured fields
- ↕️ Column sorting
- ⚡ Bulk record deletion
- 📱 Responsive design
- 🎨 Custom icons and styling
- 🔒 Built-in security checks and permissions handling
- ↔️ Resizable columns
- 🔄 Flow integration
- 🏠 Support for compound fields (like MailingAddress)

## Component Configuration

### Required Properties
```javascript
<c-advanced-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone"
    searchable-fields="Name,Email"
    records-per-page="10">
</c-advanced-related-list>
```

### Configuration Options

| Property | Description | Required | Default |
|----------|-------------|----------|---------|
| childObjectApiName | API name of the child object (e.g., Contact) | Yes | - |
| parentLookupField | API name of the lookup field on child object (e.g., AccountId) | Yes | - |
| fieldsToDisplay | Comma-separated list of fields to display | Yes | - |
| searchableFields | Comma-separated list of fields to enable search | Yes | - |
| recordsPerPage | Number of records per page | No | 10 |
| flowName | API name of a flow to launch | No | - |
| flowTitle | Title for the flow modal | No | "Run Flow" |
| listTitle | Custom title for the related list | No | "[Object] Related List" |
| customIconName | SLDS icon name | No | - |
| iconBackgroundColor | Background color for the icon | No | "#f4b400" |
| columnLabels | Custom labels for columns | No | - |
| sortableFields | Fields that can be sorted | No | - |

## Usage Examples

### Basic Configuration
```javascript
<c-advanced-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone,Title"
    searchable-fields="Name,Email"
    records-per-page="5">
</c-advanced-related-list>
```

### Configuration with Compound Fields
```javascript
<c-advanced-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone,MailingAddress"
    searchable-fields="Name,Email"
    records-per-page="10"
    column-labels="Name,Email,Phone,Address">
</c-advanced-related-list>
```

### Advanced Configuration with Flow and Compound Fields
```javascript
<c-advanced-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone,MailingAddress,Account.Name"
    searchable-fields="Name,Email,Phone"
    records-per-page="10"
    flow-name="Contact_Update_Flow"
    flow-title="Update Contact"
    list-title="Customer Contacts"
    custom-icon-name="standard:contact"
    icon-background-color="#1589EE"
    column-labels="Full Name,Email Address,Phone Number,Mailing Address,Account"
    sortable-fields="Name,Email">
</c-advanced-related-list>
```

## Component Features

### Compound Fields Support
- Support for standard compound fields like MailingAddress and BillingAddress
- Automatic formatting of address components into a single column
- Clean address display with proper formatting
- Works seamlessly with other features like sorting and searching

[Previous sections remain the same...]

## Limitations

- Maximum 100 records can be selected for bulk operations
- Column width customization is saved per session only
- Custom icons must use SLDS icon names
- Flow inputs are limited to recordId
- Compound fields are displayed as read-only
- Search on compound fields searches the individual components

## Support & Contribution

For issues, questions, or contributions, please raise them through the GitHub repository or contact the package owner.

## Release Notes

### Version 1.1.0
- Added support for compound fields (MailingAddress, BillingAddress)
- Improved address formatting and display
- Enhanced field handling for complex field types

### Version 1.0.0
- Initial release with core functionality
- Pagination, search, and bulk delete features
- Flow integration capability
- Responsive design implementation
