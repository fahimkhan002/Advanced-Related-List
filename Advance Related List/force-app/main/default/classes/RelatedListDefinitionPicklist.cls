/**
 * @description Lightning App Builder datasource for the "List Definition Key" property: a dropdown
 *              of active definitions whose Parent Object matches the page being edited, so admins pick
 *              a definition instead of typing its DeveloperName. Design-time only; it grants nothing.
 */
global with sharing class RelatedListDefinitionPicklist extends VisualEditor.DynamicPickList {
    private final String pageObject;

    /**
     * @description Constructed by App Builder with the page context.
     * @param context design-time page context
     */
    global RelatedListDefinitionPicklist(VisualEditor.DesignTimePageContext context) {
        this.pageObject = context == null ? null : context.entityName;
    }

    /**
     * @description No default: a blank key keeps the legacy App Builder properties in charge.
     * @return null
     */
    global override VisualEditor.DataRow getDefaultValue() {
        return null;
    }

    /**
     * @description Active definitions for the page's object (all active ones when the object is unknown).
     * @return rows labelled "Label (Child via Lookup)"
     */
    global override VisualEditor.DynamicPickListRows getValues() {
        VisualEditor.DynamicPickListRows rows = new VisualEditor.DynamicPickListRows();
        for (Advanced_Related_List__mdt def : [
            SELECT DeveloperName, MasterLabel, Parent_Object__c, Child_Object__c, Relationship_Field__c
            FROM Advanced_Related_List__mdt
            WHERE Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY MasterLabel
        ]) {
            if (String.isBlank(pageObject) || pageObject.equalsIgnoreCase(def.Parent_Object__c)) {
                String label = def.MasterLabel + ' (' + def.Child_Object__c + ' via ' + def.Relationship_Field__c + ')';
                rows.addRow(new VisualEditor.DataRow(label, def.DeveloperName));
            }
        }
        return rows;
    }
}
