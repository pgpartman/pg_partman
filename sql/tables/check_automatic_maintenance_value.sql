-- Put constraint functions & definitions here because having them in a separate file makes the ordering of their creation harder to control.

/*
 * Check for valid config values for automatic maintenance
 * (not boolean to allow future values)
 */
CREATE FUNCTION @extschema@.check_automatic_maintenance_value (p_automatic_maintenance text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_automatic_maintenance IN ('on', 'off') INTO v_result;
    RETURN v_result;
END
$$;
