CREATE FUNCTION @extschema@.check_time_encoder_decoder(
    p_time_encoder TEXT
    , p_time_decoder TEXT
    , p_control_type TEXT
    , p_start_timestamp TIMESTAMPTZ
)
    RETURNS VOID
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE

v_control_type_oid      REGTYPE;
v_i_check_rec           RECORD;
v_i_fname_parsed        TEXT[];
v_i_found_proc_row      pg_catalog.pg_proc%ROWTYPE;
v_i_null_returned_null  BOOLEAN;
v_roundtrip_result      TIMESTAMPTZ;

BEGIN
/*
 * Performs sanity checks on provided time encoder and decoder functions.
 */

SELECT p_control_type::regtype INTO STRICT v_control_type_oid;

FOR v_i_check_rec IN
    WITH loops(fname, ftypin, ftypout) AS (VALUES
        (p_time_encoder, 'TIMESTAMPTZ'::regtype, v_control_type_oid),
        (p_time_decoder, v_control_type_oid, 'TIMESTAMPTZ'::regtype)
    )
    SELECT * FROM loops
LOOP
    -- Make sure the function name is valid and schema qualified
    v_i_fname_parsed := parse_ident(v_i_check_rec.fname);
    IF cardinality(v_i_fname_parsed) <> 2 THEN
        RAISE EXCEPTION 'The function name % is not a valid fully qualified name.', v_i_check_rec.fname;
    END IF;

    -- Check the functions exist with exact parameter/return types
    BEGIN
        SELECT * INTO STRICT v_i_found_proc_row
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = v_i_fname_parsed[1] AND proname = v_i_fname_parsed[2]
        AND pronargs >= 1 and proargtypes[0] = v_i_check_rec.ftypin
        AND prorettype = v_i_check_rec.ftypout;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE EXCEPTION 'No function named % matching argument % and returning %.', v_i_check_rec.fname, v_i_check_rec.ftypin, ftypout;
            WHEN TOO_MANY_ROWS THEN
                RAISE EXCEPTION 'Function %(%) -> % is ambiguous, this should not happen.', v_i_check_rec.fname, v_i_check_rec.ftypin, ftypout;
    END;

    -- Check that the function is declared IMMUTABLE
    IF v_i_found_proc_row.provolatile <> 'i' THEN
        RAISE EXCEPTION 'Function % must be declared IMMUTABLE (got %).', v_i_check_rec.fname, CASE v_i_found_proc_row.provolatile WHEN 's' THEN 'STABLE' WHEN 'v' THEN 'VOLATILE' END;
    END IF;

    -- Check that the functions return NULL when passed a NULL
    EXECUTE FORMAT('SELECT %s(NULL) IS NULL', v_i_check_rec.fname) INTO v_i_null_returned_null;

    IF NOT v_i_null_returned_null THEN
        RAISE EXCEPTION 'Function % does not return NULL when called on NULL.', v_i_check_rec.fname;
    END IF;

    -- Show performance warning for default of PARALLEL UNSAFE
    IF v_i_found_proc_row.proparallel <> 's' THEN
        RAISE NOTICE 'Function % is not declared parallel safe, this may affect performance if you use it for predicates. See the documentation for CREATE FUNCTION.', v_i_check_rec.fname;
    END IF;

END LOOP;

-- test roundtrip
EXECUTE FORMAT('SELECT %s(%s(%L))', p_time_decoder, p_time_encoder, p_start_timestamp) INTO v_roundtrip_result;

IF p_start_timestamp <> v_roundtrip_result THEN
    RAISE EXCEPTION 'Encoding and then decoding the start of the first partition range (%) got a different value (%). Make sure the encoding is correct and aligns with the partition interval.', p_start_timestamp, v_roundtrip_result;
END IF;

END
$$;
