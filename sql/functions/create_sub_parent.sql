CREATE FUNCTION @extschema@.create_sub_parent(
    p_top_parent text
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_default_table boolean DEFAULT true
    , p_declarative_check text DEFAULT NULL
    , p_constraint_cols text[] DEFAULT NULL
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_epoch text DEFAULT 'none'
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
    , p_control_not_null boolean DEFAULT true
    , p_time_encoder text DEFAULT NULL
    , p_time_decoder text DEFAULT NULL
)
    RETURNS boolean
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

BEGIN
/*
    This is an alias function for create_sub_partition() for backward compatibility
*/

RETURN @extschema@.create_sub_partition(
    p_top_parent
    , p_control
    , p_interval
    , p_type
    , p_default_table
    , p_declarative_check
    , p_constraint_cols
    , p_premake
    , p_start_partition
    , p_epoch
    , p_jobmon
    , p_date_trunc_interval
    , p_control_not_null
    , p_time_encoder
    , p_time_decoder
);

END
$$;
