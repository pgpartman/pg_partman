CREATE FUNCTION @extschema@.partman_safe_obj_name(
    p_object_name text
)
    RETURNS text
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE
    v_obj_part1     text;
    v_obj_part2     text;
    v_obj_safe      text;
BEGIN

    v_obj_part1 := split_part(p_object_name, '.', 1);
    v_obj_part2 := split_part(p_object_name, '.', 2);

    IF v_obj_part2 = '' THEN
        v_obj_safe := format('%I', v_obj_part1);
    ELSE
        v_obj_safe := format('%I.%I', v_obj_part1, v_obj_part2);
    END IF;

    RETURN v_obj_safe;

END
$$;

