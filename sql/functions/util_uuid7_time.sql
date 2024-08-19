/*
 * Convenience helper functions to support time based partitioning for UUIDv7 columns.
 * Set the following functions as p_time_encoder, p_time_decoder params for time based
 * partitioning of UUIDv7 columns
 */

CREATE FUNCTION @extschema@.uuid7_time_encoder(ts TIMESTAMPTZ)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    ts_millis BIGINT;
    ts_hex TEXT;
BEGIN
    -- Convert the milliseconds to a 12 char hex with zero pad
    ts_millis := EXTRACT(EPOCH FROM ts) * 1000;
    ts_hex := lpad(to_hex(ts_millis), 12, '0');

    -- Split the timestamp into two parts as per spec
    RETURN substr(ts_hex, 1, 8) || '-' || substr(ts_hex, 9, 4) || '-0000-0000-000000000000';
END;
$$;

CREATE FUNCTION @extschema@.uuid7_time_decoder(uuidv7 TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
AS $$
DECLARE
    ts_hex TEXT;
    ts_millis BIGINT;
    extracted_ts TIMESTAMPTZ;
BEGIN
    -- Extract the first 12 characters of the UUID which represent the timestamp
    ts_hex := substr(uuidv7::TEXT, 1, 8) || substr(uuidv7::TEXT, 10, 4);

    -- Convert the hex timestamp to a BIGINT (milliseconds)
    ts_millis := ('x' || ts_hex)::BIT(48)::BIGINT;

    RETURN to_timestamp(ts_millis / 1000.0);
END;
$$;
