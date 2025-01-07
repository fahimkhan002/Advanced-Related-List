# Salesforce LWC Related List Component

A highly customizable Lightning Web Component (LWC) that provides enhanced related list functionality for Salesforce with features like server-side pagination, dynamic sorting, global search, and relationship field support.

## Features

- **Server-side Pagination**: Efficiently handle large datasets with configurable page sizes
- **Dynamic Sorting**: Sort any column including relationship fields
- **Global Search**: Search across all records (not just the current page) including relationship fields
- **Responsive Design**: Adapts to different screen sizes
- **Custom Icons**: Support for custom icons with configurable background colors
- **Flow Integration**: Launch flows directly from the related list
- **CRUD Operations**: 
  - Create new records
  - Edit existing records
  - Delete records with confirmation
- **Toast Notifications**: User-friendly feedback messages
- **Loading States**: Visual feedback during data operations

## Component Properties

| Property Name | Type | Required | Description | Example |
|--------------|------|----------|-------------|---------|
| childObjectApiName | String | Yes | API name of the child object | `'Hospital_Affiliation__c'` |
| parentLookupField | String | Yes | API name of the lookup field in child object | `'Provider__c'` |
| fieldsToDisplay | String | Yes | Comma-separated list of field API names | `'Name,Status__c'` |
| columnLabels | String | No | Custom labels for columns | `'Name,Status'` |
| searchableFields | String | Yes | Fields to enable in search | `'Name,Status__c'` |
| recordsPerPage | Integer | No | Number of records per page (default: 10) | `20` |
| flowName | String | No | API name of the flow to launch | `'Update_Status'` |
| flowTitle | String | No | Title for the flow modal | `'Update Status'` |
| listTitle | String | No | Custom title for the related list | `'Hospital Affiliations'` |
| customIconName | String | No | SLDS icon name | `'standard:account'` |
| iconBackgroundColor | String | No | Background color for icon | `'#f4b400'` |

## Installation

1. Deploy the following components to your Salesforce org:
   - `RelatedList` LWC component
   - `RelatedListController` Apex class

2. Add the component to your Lightning page using the Lightning App Builder:
   ```html
   <c-related-list
       child-object-api-name="Hospital_Affiliation__c"
       parent-lookup-field="Provider__c"
       fields-to-display="Name,Credentialing_Entity__r.Name,Status__c"
       searchable-fields="Name,Credentialing_Entity__r.Name,Status__c"
       records-per-page="20"
       list-title="Hospital Affiliations">
   </c-related-list>
   ```

## Usage Example

### Basic Implementation
```html
<c-related-list
    child-object-api-name="Hospital_Affiliation__c"
    parent-lookup-field="Provider__c"
    fields-to-display="Name,Status__c"
    searchable-fields="Name,Status__c">
</c-related-list>
```

### Advanced Implementation with Flow
```html
<c-related-list
    child-object-api-name="Hospital_Affiliation__c"
    parent-lookup-field="Provider__c"
    fields-to-display="Name,Credentialing_Entity__r.Name,Status__c"
    searchable-fields="Name,Credentialing_Entity__r.Name,Status__c"
    records-per-page="20"
    flow-name="Update_Hospital_Status"
    flow-title="Update Status"
    list-title="Hospital Affiliations"
    custom-icon-name="standard:hospital"
    icon-background-color="#1589EE">
</c-related-list>
```

## Component Structure

```
force-app/main/default/
├── classes/
│   └── RelatedListController.cls
└── lwc/
    └── relatedList/
        ├── relatedList.js
        ├── relatedList.html
        └── relatedList.js-meta.xml
```

## Key Features Explained

### Server-side Pagination
The component uses server-side pagination to efficiently handle large datasets. The page size is configurable through the `recordsPerPage` property.

### Global Search
Search functionality works across the entire dataset, not just the current page. It supports both regular and relationship fields.

### Relationship Fields
The component properly handles relationship fields for both display and search operations. For example, `Credentialing_Entity__r.Name` will work in both display and search contexts.

### Dynamic Sorting
All displayed fields can be sorted, including relationship fields. The sorting is maintained during pagination and search operations.

## Best Practices

1. **Field Selection**: Only include necessary fields in `fieldsToDisplay` to optimize performance
2. **Search Fields**: Choose searchable fields carefully to maintain performance
3. **Page Size**: Consider data volume when setting `recordsPerPage`
4. **Error Handling**: The component includes built-in error handling with user-friendly messages

## Contributing

Feel free to submit issues and enhancement requests!

## License
