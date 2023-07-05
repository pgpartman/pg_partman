-- Put constraint functions & definitions here because having them in a separate file makes the ordering of their creation harder to control.

/*
 * Check function for config table epoch types
 */
CREATE FUNCTION @extschema@.check_epoch_type (p_type text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_type IN ('none', 'seconds', 'milliseconds', 'nanoseconds') INTO v_result;
    RETURN v_result;
END
$$;
