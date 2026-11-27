/**
 * @description Categorised, user-safe exception for the Advanced Related List.
 *              Messages must never contain record data, stack traces or query text.
 */
public inherited sharing class RelatedListException extends Exception {
    /** @description Category of failure, mapped to a response status by the controller. */
    public enum Category {
        CONFIG,
        ACCESS,
        INPUT,
        STALE
    }

    public Category category = Category.INPUT;

    /**
     * @description Configuration problem an administrator can fix (unknown field, inactive definition...).
     * @param message actionable admin-facing message
     * @return exception instance
     */
    public static RelatedListException config(String message) {
        return build(Category.CONFIG, message);
    }

    /**
     * @description The running user lacks access. Never reveals whether a record exists.
     * @param message user-facing message
     * @return exception instance
     */
    public static RelatedListException access(String message) {
        return build(Category.ACCESS, message);
    }

    /**
     * @description Invalid request input (bad operator, value, bounds).
     * @param message user-facing message
     * @return exception instance
     */
    public static RelatedListException input(String message) {
        return build(Category.INPUT, message);
    }

    /**
     * @description Pagination cursor no longer matches the current query.
     * @return exception instance
     */
    public static RelatedListException stale() {
        return build(Category.STALE, 'The list changed. Showing the first page.');
    }

    private static RelatedListException build(Category category, String message) {
        RelatedListException ex = new RelatedListException(message);
        ex.category = category;
        return ex;
    }
}
