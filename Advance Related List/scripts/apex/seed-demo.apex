// Repeatable synthetic demo data for Advanced Related List v2 (scratch org only).
// Re-running it creates nothing new: accounts are matched by name, opportunities by name per account.
String NORTHWIND = 'ARL Demo - Northwind Traders';
String CONTOSO = 'ARL Demo - Contoso Partners';

List<String> stages = new List<String>();
for (Schema.PicklistEntry e : Opportunity.StageName.getDescribe().getPicklistValues()) {
    if (e.isActive()) { stages.add(e.getValue()); }
}

Map<String, Account> accounts = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :new List<String>{ NORTHWIND, CONTOSO }]) {
    accounts.put(a.Name, a);
}
List<Account> newAccounts = new List<Account>();
for (String name : new List<String>{ NORTHWIND, CONTOSO }) {
    if (!accounts.containsKey(name)) { newAccounts.add(new Account(Name = name, Industry = 'Technology')); }
}
insert newAccounts;
for (Account a : newAccounts) { accounts.put(a.Name, a); }

// name, amount, days from today
List<List<Object>> northwind = new List<List<Object>>{
    new List<Object>{ 'Northwind - Analytics Platform', 125000, 12 },
    new List<Object>{ 'Northwind - Support Renewal 2027', 18000, 30 },
    new List<Object>{ 'Northwind - Warehouse Sensors', 64000, 45 },
    new List<Object>{ 'Northwind - Fleet Telematics', 210000, 60 },
    new List<Object>{ 'Northwind - Training Package', 9500, 7 },
    new List<Object>{ 'Northwind - Security Renewal', 18000, 90 },
    new List<Object>{ 'Northwind - EMEA Expansion', 340000, 120 },
    new List<Object>{ 'Northwind - Data Migration', 42000, 21 },
    new List<Object>{ 'Northwind - Mobile App Pilot', 27500, 75 },
    new List<Object>{ 'Northwind - Licence True-up', 5200, -14 },
    new List<Object>{ 'Northwind - Consulting Renewal', 76000, 150 },
    new List<Object>{ 'Northwind - Edge Gateways', 98000, 180 },
    new List<Object>{ 'Northwind - Partner Portal', 54000, 210 },
    new List<Object>{ 'Northwind - AI Forecasting', 156000, 240 }
};
List<List<Object>> contoso = new List<List<Object>>{
    new List<Object>{ 'Contoso - Starter Bundle', 12000, 10 },
    new List<Object>{ 'Contoso - Annual Renewal', 33000, 40 },
    new List<Object>{ 'Contoso - Integration Services', 71000, 95 }
};

Map<Id, List<List<Object>>> plan = new Map<Id, List<List<Object>>>{
    accounts.get(NORTHWIND).Id => northwind,
    accounts.get(CONTOSO).Id => contoso
};
Set<String> existing = new Set<String>();
for (Opportunity o : [SELECT AccountId, Name FROM Opportunity WHERE AccountId IN :plan.keySet()]) {
    existing.add(o.AccountId + '|' + o.Name);
}
List<Opportunity> opps = new List<Opportunity>();
Integer i = 0;
for (Id accountId : plan.keySet()) {
    for (List<Object> row : plan.get(accountId)) {
        String name = (String) row[0];
        if (!existing.contains(accountId + '|' + name)) {
            opps.add(new Opportunity(
                AccountId = accountId,
                Name = name,
                Amount = (Integer) row[1],
                CloseDate = Date.today().addDays((Integer) row[2]),
                StageName = stages[Math.mod(i, stages.size())]
            ));
        }
        i++;
    }
}
insert opps;
System.debug(LoggingLevel.INFO, 'ARL_SEED accounts=' + accounts.size() + ' newAccounts=' + newAccounts.size() + ' newOpportunities=' + opps.size());
