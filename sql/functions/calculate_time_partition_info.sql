CREATE FUNCTION @extschema@.calculate_time_partition_info(
        p_time_interval interval
        , p_start_time timestamptz
        , p_date_trunc_interval text DEFAULT NULL
        , p_timezone text DEFAULT NULL
        , OUT base_timestamp timestamptz
        , OUT datetime_string text
)
    RETURNS record
    LANGUAGE plpgsql STABLE
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

v_timezone  text := COALESCE(p_timezone, current_setting('TimeZone'));

BEGIN

-- Built-in datetime string suffixes are YYYYMMDD, YYYYMMDD_HH24MISS
datetime_string := 'YYYYMMDD';
IF p_time_interval < '1 day' THEN
    datetime_string := datetime_string || '_HH24MISS';
END IF;

-- Truncation is done in the partition set's own timezone (v_timezone) so that
-- boundaries stay aligned regardless of the session timezone maintenance runs
-- in. When p_timezone is NULL the current session timezone is used, which is
-- exactly the historical behavior. See date_trunc() below via AT TIME ZONE.

IF p_date_trunc_interval IS NOT NULL THEN
    base_timestamp := date_trunc(p_date_trunc_interval, p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;

ELSE
    IF p_time_interval >= '1 year' THEN
        base_timestamp := date_trunc('year', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
        IF p_time_interval >= '10 years' THEN
            base_timestamp := date_trunc('decade', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
            IF p_time_interval >= '100 years' THEN
                base_timestamp := date_trunc('century', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
                IF p_time_interval >= '1000 years' THEN
                    base_timestamp := date_trunc('millennium', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
                END IF; -- 1000
            END IF; -- 100
        END IF; -- 10
    END IF; -- 1

    IF p_time_interval < '1 year' THEN
        base_timestamp := date_trunc('month', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
        IF p_time_interval < '1 month' THEN
            base_timestamp := date_trunc('day', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
            IF p_time_interval < '1 day' THEN
                base_timestamp := date_trunc('hour', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
                IF p_time_interval < '1 minute' THEN
                    base_timestamp := date_trunc('minute', p_start_time AT TIME ZONE v_timezone) AT TIME ZONE v_timezone;
                END IF; -- minute
            END IF; -- day
        END IF; -- month
    END IF; -- year

END IF;
END
$$;
