# Advanced Related List LWC Component

A flexible Lightning Web Component that provides an enhanced related list experience in Salesforce with features like pagination, search, sorting, bulk actions, advanced filtering, and more.

## Installation

### Option 1: Package Installation (Recommended)
1. Install the package in production using this URL:
   ```
   https://login.salesforce.com/packaging/installPackage.apexp?p0=04tJ30000008qfj
   ```
   and for sandbox:
   ```
   https://test.salesforce.com/packaging/installPackage.apexp?p0=04tJ30000008qfj
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
   - `filterPanel.js`
   - `filterPanel.html`
   - `filterPanel.js-meta.xml`

## Features

- ✨ Pagination with configurable page size
- 🔍 Real-time search across configured fields
- 🎯 Advanced filtering panel with multiple conditions
- ↕️ Column sorting
- ⚡ Bulk record deletion
- 📱 Responsive design
- 🎨 Custom icons and styling
- 🔒 Enhanced security checks and permissions handling
- ↔️ Resizable columns with persistence
- 🔄 Flow integration
- 🏠 Support for compound fields (like MailingAddress)
- 🔐 Field-level security enforcement
- 📊 Dynamic filter operations (equals, contains, starts with, etc.)

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

## Advanced Features

### Filter Panel
The component now includes a powerful filter panel that allows users to:
- Create multiple filter conditions
- Combine conditions with AND/OR operators
- Use various comparison operators:
  - equals
  - not equal to
  - contains
  - does not contain
  - starts with
  - ends with
  - less than
  - greater than

Example of filter configuration:
```javascript
[
    {
        field: "LastName",
        operator: "STARTS",
        value: "Smith",
        logicOperator: "AND"
    },
    {
        field: "Email",
        operator: "CONTAINS",
        value: "@example.com",
        logicOperator: "OR"
    }
]
```

### Enhanced Security
The component implements comprehensive security measures:
- Object-level CRUD permission checks
- Field-level security enforcement
- Validation of all user inputs
- Secure query building with proper escaping
- Permission-based action visibility
- Custom error messaging for permission issues

### Address Field Handling
Improved handling of compound address fields:
- Support for all standard address fields (Mailing, Shipping, Billing, Other)
- Automatic component separation and formatting
- Proper search functionality across address components
- Responsive display formatting

## Usage Examples

### Basic Configuration with Filter Panel
```javascript
<c-advanced-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone,Title"
    searchable-fields="Name,Email"
    records-per-page="5">
</c-advanced-related-list>
```

### Advanced Configuration with All Features
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

## Component Architecture

### Main Components
1. **AdvanceRelatedList** (Parent Component)
   - Handles main UI and data operations
   - Manages state and user interactions
   - Coordinates between child components

2. **FilterPanel** (Child Component)
   - Manages filter UI and logic
   - Handles filter combinations
   - Provides dynamic operator selection

### Controllers
- **RelatedListController**
  - Implements secure SOQL query building
  - Handles permission checks
  - Processes filter conditions
  - Manages CRUD operations

## Limitations

- Maximum 100 records can be selected for bulk operations
- Column width customization persists per session
- Custom icons must use SLDS icon names
- Flow inputs are limited to recordId
- Compound fields are displayed as read-only
- Search on compound fields searches individual components
- Filter conditions are limited to AND/OR combinations
- Maximum of 20 concurrent filter conditions

## Troubleshooting

### Common Issues and Solutions
1. **Permission Errors**
   - Verify user profile permissions
   - Check field-level security settings
   - Ensure proper object access

2. **Performance Issues**
   - Reduce number of displayed fields
   - Index frequently filtered fields
   - Optimize search field selection

3. **Filter Panel Issues**
   - Verify field API names
   - Check field types match operators
   - Ensure proper field accessibility

## Release Notes

### Version 1.2.0
- Added advanced filter panel functionality
- Enhanced security implementations
- Improved error handling and messaging
- Added field-level security enforcement
- Implemented persistent column widths

### Version 1.1.0
- Added support for compound fields
- Improved address formatting
- Enhanced field handling

### Version 1.0.0
- Initial release with core functionality

## Support & Contribution

For issues, questions, or contributions, please raise them through the GitHub repository or contact the package owner.

## License

This component is released under the MIT License.
