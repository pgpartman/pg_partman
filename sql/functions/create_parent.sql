CREATE FUNCTION @extschema@.create_parent(
    p_parent_table text
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_epoch text DEFAULT 'none'
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_default_table boolean DEFAULT true
    , p_automatic_maintenance text DEFAULT 'on'
    , p_constraint_cols text[] DEFAULT NULL
    , p_template_table text DEFAULT NULL
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
    , p_control_not_null boolean DEFAULT true
    , p_time_encoder text DEFAULT NULL
    , p_time_decoder text DEFAULT NULL
    , p_offset_id bigint DEFAULT 0
)
    RETURNS boolean
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

BEGIN
/*
    This is an alias function for create_partition() for backward compatibility
*/

RETURN @extschema@.create_partition(
    p_parent_table
    , p_control
    , p_interval
    , p_type
    , p_epoch
    , p_premake
    , p_start_partition
    , p_default_table
    , p_automatic_maintenance
    , p_constraint_cols
    , p_template_table
    , p_jobmon
    , p_date_trunc_interval
    , p_control_not_null
    , p_time_encoder
    , p_time_decoder
    , p_offset_id
);

END
$$;
