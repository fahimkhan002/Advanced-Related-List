// Read-only check of the Account_Opportunities demo through the real controller endpoint.
Id northwind = [SELECT Id FROM Account WHERE Name = 'ARL Demo - Northwind Traders' LIMIT 1].Id;
Id contoso = [SELECT Id FROM Account WHERE Name = 'ARL Demo - Contoso Partners' LIMIT 1].Id;

RelatedListController.ListRequest req = new RelatedListController.ListRequest();
req.definitionKey = 'Account_Opportunities';
req.parentId = northwind;
req.pageSize = 5;
req.filters = new List<RelatedListController.FilterInput>();
RelatedListController.ListResponse p1 = RelatedListController.getRows(req);
List<String> cols = new List<String>();
for (RelatedListController.ColumnInfo c : p1.columns) {
    cols.add(c.key + '=' + c.label + '[' + c.type + (c.searchable ? ',search' : '') + (c.filterable ? ',filter' : '') + (c.sortable ? ',sort' : '') + ']');
}
System.debug(LoggingLevel.ERROR, 'ARL_VERIFY default status=' + p1.status + ' total=' + p1.totalCount + ' rows=' + p1.rows.size() + ' hasMore=' + p1.hasMore + ' sortKey=' + p1.context.sortKey + ' ' + p1.context.sortDirection);
System.debug(LoggingLevel.ERROR, 'ARL_VERIFY columns ' + String.join(cols, ' | '));

req.searchTerm = 'Renewal';
RelatedListController.ListResponse s = RelatedListController.getRows(req);
List<String> names = new List<String>();
for (Map<String, Object> r : s.rows) { names.add(String.valueOf(r.get('AO_Name'))); }
System.debug(LoggingLevel.ERROR, 'ARL_VERIFY search Renewal status=' + s.status + ' total=' + s.totalCount + ' names=' + names);

req.searchTerm = null;
String stage = [SELECT StageName FROM Opportunity WHERE AccountId = :northwind ORDER BY Name LIMIT 1].StageName;
RelatedListController.FilterInput f = new RelatedListController.FilterInput();
f.columnKey = 'AO_Stage';
f.operator = 'equals';
f.value = stage;
req.filters.add(f);
RelatedListController.ListResponse fr = RelatedListController.getRows(req);
System.debug(LoggingLevel.ERROR, 'ARL_VERIFY filter stage=' + stage + ' status=' + fr.status + ' total=' + fr.totalCount + ' expected=' + [SELECT COUNT() FROM Opportunity WHERE AccountId = :northwind AND StageName = :stage]);

req.filters.clear();
req.sortKey = 'AO_Amount';
req.sortDirection = 'desc';
List<Object> amounts = new List<Object>();
Integer pages = 0;
do {
    RelatedListController.ListResponse pg = RelatedListController.getRows(req);
    for (Map<String, Object> r : pg.rows) { amounts.add(r.get('AO_Amount')); }
    req.cursor = pg.nextCursor;
    pages++;
} while (req.cursor != null && pages < 10);
System.debug(LoggingLevel.ERROR, 'ARL_VERIFY sort Amount desc pages=' + pages + ' count=' + amounts.size() + ' amounts=' + amounts);

RelatedListController.ListRequest other = new RelatedListController.ListRequest();
other.definitionKey = 'Account_Opportunities';
other.parentId = contoso;
other.pageSize = 5;
RelatedListController.ListResponse c = RelatedListController.getRows(other);
List<String> cNames = new List<String>();
for (Map<String, Object> r : c.rows) { cNames.add(String.valueOf(r.get('AO_Name'))); }
System.debug(LoggingLevel.ERROR, 'ARL_VERIFY contoso status=' + c.status + ' total=' + c.totalCount + ' names=' + cNames);
