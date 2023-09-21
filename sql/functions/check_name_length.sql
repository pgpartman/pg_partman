CREATE FUNCTION @extschema@.check_name_length (
    p_object_name text
    , p_suffix text DEFAULT NULL
    , p_table_partition boolean DEFAULT FALSE
)
    RETURNS text
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
    AS $$
DECLARE
    v_new_name      text;
    v_suffix        text;
BEGIN
/*
 * Truncate the name of the given object if it is greater than the postgres default max (63 characters).
 * Also appends given suffix and schema if given and truncates the name so that the entire suffix will fit.
 * Returns original name (with suffix if given) if it doesn't require truncation
 * Retains SECURITY DEFINER since it is called by trigger functions and did not want to break installations prior to 4.0.0
 */

IF p_table_partition IS TRUE AND (NULLIF(p_suffix, '') IS NULL) THEN
    RAISE EXCEPTION 'Table partition name requires a suffix value';
END IF;


v_suffix := format('%s%s', CASE WHEN p_table_partition THEN '_p' END, p_suffix);
-- Use optimistic behavior: in almost all cases `v_new_name` will be less than allowed maximum.
-- Do "heavy" work only in rare cases.
v_new_name := p_object_name || v_suffix;

-- Postgres' relation name limit is in bytes, not characters; also it can be compiled with bigger allowed length.
-- Use its internals to detect where to cut new object name.
IF v_new_name::name != v_new_name THEN
    -- Here we need to detect how many chars (not bytes) we need to get from the `p_object_name`.
    -- Use suffix as prefix and get the rest of `p_object_name`.
    v_new_name := (v_suffix || p_object_name)::name;
    -- `substr` starts from 1, that is why we need to add 1 below.
    -- Edge case: `v_suffix` is empty, length is 0, but need to start from 1.
    v_new_name := substr(v_new_name, length(v_suffix) + 1) || v_suffix;
END IF;

RETURN v_new_name;

END
$$;
