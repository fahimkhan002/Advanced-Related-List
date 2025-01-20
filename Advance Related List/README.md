# Advanced Salesforce LWC Related List Component

A highly customizable Lightning Web Component (LWC) that provides enhanced related list functionality for Salesforce. This component combines powerful features like server-side pagination, dynamic sorting, global search, and comprehensive field type support.

## 🚀 Features

### Core Features
- **Server-side Pagination**: Efficiently handle large datasets
- **Dynamic Sorting**: Sort any column including relationship fields
- **Global Search**: Search across all records and relationship fields
- **Responsive Design**: Adapts to different screen sizes
- **CRUD Operations**: Full create, read, update, delete support

### Advanced Features
- **Field Type Support**:
  - 📧 Email fields with click-to-email
  - 📞 Phone fields with click-to-call
  - 💰 Currency fields with proper formatting
  - 📅 Date/Time with locale support
  - 🔗 Lookup fields with navigation
  - ✅ Boolean fields
  - 📊 Number and percent fields
  - 📝 Rich text support

### User Experience
- **Column Management**: 
  - Resizable columns
  - Custom column labels
  - Reset to default widths
- **Interactive Elements**:
  - Loading states
  - Toast notifications
  - Confirmation dialogs
- **Flow Integration**: Launch flows from the related list
- **Bulk Operations**: Select and delete multiple records

## 📋 Component Properties

| Property Name | Type | Required | Description | Default | Example |
|--------------|------|----------|-------------|---------|---------|
| childObjectApiName | String | Yes | Child object API name | - | `'Contact'` |
| parentLookupField | String | Yes | Lookup field API name | - | `'AccountId'` |
| fieldsToDisplay | String | Yes | Fields to show | - | `'Name,Email,Phone'` |
| columnLabels | String | No | Custom column labels | Field labels | `'Name,Email,Phone'` |
| searchableFields | String | Yes | Searchable fields | - | `'Name,Email'` |
| sortableFields | String | No | Sortable fields | All fields | `'Name,CreatedDate'` |
| recordsPerPage | Integer | No | Records per page | 10 | `20` |
| flowName | String | No | Flow API name | - | `'Update_Contact'` |
| flowTitle | String | No | Flow modal title | 'Run Flow' | `'Update Contact'` |
| listTitle | String | No | List title | Object label | `'Contacts'` |
| customIconName | String | No | SLDS icon name | 'standard:custom' | `'standard:contact'` |
| iconBackgroundColor | String | No | Icon background color | '#f4b400' | `'#1589EE'` |

## 🛠️ Installation

1. Deploy these components to your org:
```bash
force-app/main/default/
├── classes/
│   ├── RelatedListController.cls
│   └── RelatedListControllerTest.cls
└── lwc/
    └── advanceRelatedList/
        ├── advanceRelatedList.js
        ├── advanceRelatedList.html
        ├── advanceRelatedList.css
        └── advanceRelatedList.js-meta.xml
```

2. Assign appropriate permissions to profiles that need access.

## 📝 Usage Examples

### Basic Implementation
```html
<c-advance-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone"
    searchable-fields="Name,Email">
</c-advance-related-list>
```

### Advanced Implementation
```html
<c-advance-related-list
    child-object-api-name="Contact"
    parent-lookup-field="AccountId"
    fields-to-display="Name,Email,Phone,Title,Account.Name,CreatedDate"
    searchable-fields="Name,Email,Title,Account.Name"
    sortable-fields="Name,CreatedDate"
    column-labels="Full Name,Email,Phone,Title,Account,Created"
    records-per-page="15"
    flow-name="Contact_Update_Flow"
    flow-title="Update Contact"
    list-title="Customer Contacts"
    custom-icon-name="standard:contact"
    icon-background-color="#1589EE">
</c-advance-related-list>
```

## 🎯 Key Features Explained

### Server-side Pagination
- Efficient handling of large datasets
- Configurable page sizes
- Maintains state during operations

### Global Search
- Searches entire dataset, not just current page
- Supports relationship fields
- Real-time search with debouncing
- Case-insensitive matching

### Field Type Support
- Automatic handling of different field types
- Clickable emails and phone numbers
- Proper formatting for numbers and currencies
- Date/time localization
- Relationship field navigation

## 💡 Best Practices

1. **Performance Optimization**
   - Include only necessary fields
   - Set appropriate page sizes
   - Index searchable fields

2. **Search Configuration**
   - Choose searchable fields strategically
   - Consider performance impact
   - Test with large datasets

3. **Mobile Considerations**
   - Test on mobile devices
   - Limit columns for mobile
   - Consider field types for mobile use

4. **Error Handling**
   - Monitor performance
   - Handle null values
   - Implement proper error catching

## ⚠️ Limitations

- Maximum 100 records for bulk selection
- Rich text shown as plain text in table
- Some field types have limited mobile functionality

## 🧪 Testing

Run the included test class:
```bash
sfdx force:apex:test:run -n "RelatedListControllerTest" -r human
```

## 🤝 Contributing

Pull requests welcome! For major changes, please open an issue first.

## 📄 License

[MIT](https://choosealicense.com/licenses/mit/)

## 💬 Support

For issues, feature requests, or support:
1. Check existing issues
2. Open a new issue with:
   - Clear description
   - Steps to reproduce
   - Expected behavior
   - Screenshots if applicable