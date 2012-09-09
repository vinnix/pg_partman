CREATE OR REPLACE FUNCTION part.create_parent(p_parent_table text, p_control text, p_type part.partition_type, p_interval text, p_premake int DEFAULT 3, p_debug boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE

v_datetime_string       text;
v_interval              interval;
v_last_partition_name   text;
v_partition_time        timestamp[];
v_record                record;
v_tablename             text;

BEGIN

SELECT tablename INTO v_tablename FROM pg_tables WHERE schemaname || '.' || tablename = p_parent_table;
    IF v_tablename IS NULL THEN
        RAISE EXCEPTION 'Please create given parent table first: %', p_parent_table;
    END IF;

IF p_type = 'id-static' OR p_type = 'id-dynamic' THEN
    RAISE EXCEPTION 'ID partitioning not supported yet. Try again later!';
END IF;

EXECUTE 'LOCK TABLE '||p_parent_table||' IN ACCESS EXCLUSIVE MODE';

CASE
    WHEN p_interval = 'yearly' THEN
        v_interval = '1 year';
        v_datetime_string := 'YYYY';
    WHEN p_interval = 'monthly' THEN
        v_interval = '1 month';
        v_datetime_string := 'YYYY_MM';
    WHEN p_interval = 'weekly' THEN
        v_interval = '1 week';
        v_datetime_string := 'IYYY"w"IW';
    WHEN p_interval = 'daily' THEN
        v_interval = '1 day';
        v_datetime_string := 'YYYY_MM_DD';
    WHEN p_interval = 'hourly' THEN
        v_interval = '1 hour';
        v_datetime_string := 'YYYY_MM_DD_HH24MI';
    WHEN p_interval = 'half-hour' THEN
        v_interval = '30 mins';
        v_datetime_string := 'YYYY_MM_DD_HH24MI';
    WHEN p_interval = 'quarter-hour' THEN
        v_interval = '15 mins';
        v_datetime_string := 'YYYY_MM_DD_HH24MI';
    ELSE
        v_interval := p_interval::int;
END CASE;

EXECUTE 'SELECT * FROM '||p_parent_table||' LIMIT 1' INTO v_record;
IF v_record IS NOT NULL THEN
    IF position('.' in p_parent_table) > 0 THEN 
        v_tablename := substring(p_parent_table from position('.' in p_parent_table)+1);
    END IF;

    EXECUTE 'ALTER TABLE '||p_parent_table||' RENAME TO '||v_tablename||'_pre_partition';
    EXECUTE 'CREATE TABLE '||p_parent_table||' (LIKE '||p_parent_table||'_pre_partition 
        INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING COMMENTS)';

END IF;

IF p_type = 'time-static' OR p_type = 'time-dynamic' THEN
    FOR i IN 0..p_premake LOOP
        v_partition_time := array_append(v_partition_time, quote_literal(CURRENT_TIMESTAMP + (v_interval*i))::timestamp);
    END LOOP;

    EXECUTE 'SELECT part.create_time_partition('||quote_literal(p_parent_table)||','||quote_literal(p_control)||','
        ||quote_literal(v_interval)||','||quote_literal(v_datetime_string)||','||quote_literal(v_partition_time)||')' INTO v_last_partition_name;
END IF;

INSERT INTO part.part_config (parent_table, type, part_interval, control, premake, datetime_string, last_partition) VALUES
        (p_parent_table, p_type, v_interval, p_control, p_premake, v_datetime_string, v_last_partition_name);

IF p_type = 'time-static' OR p_type = 'time-dynamic' THEN
    EXECUTE 'SELECT part.create_time_function('||quote_literal(p_parent_table)||')';
END IF;

EXECUTE 'SELECT part.create_trigger('||quote_literal(p_parent_table)||')';

EXCEPTION
    -- Catch if the conversion of the p_interval parameter to an integer doesn't work
    WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'Check interval parameter to ensure it is either a valid time period or an integer value for serial partitioning: %', SQLERRM;
END
$$;
