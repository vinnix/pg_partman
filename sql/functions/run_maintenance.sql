CREATE OR REPLACE FUNCTION part.run_maintenance() RETURNS void 
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE

v_datetime_string               text;
v_current_partition_timestamp   timestamp;
v_last_partition_timestamp      timestamp;
v_premade_count                 int;
v_row                           record;
v_sql                           text;

BEGIN

v_sql := 'SELECT parent_table
    , type
    , part_interval::interval
    , control
    , last_partition
FROM part.part_config where type = ''time-static'' or type = ''time-dynamic''';

FOR v_row IN 
SELECT parent_table
    , type
    , part_interval::interval
    , control
    , premake
    , datetime_string
    , last_partition
FROM part.part_config WHERE type = 'time-static' OR type = 'time-dynamic'
LOOP
    
    CASE
        WHEN v_row.part_interval = '15 mins' THEN
            v_current_partition_timestamp := date_trunc('hour', CURRENT_TIMESTAMP) + 
                '15min'::interval * floor(date_part('minute', CURRENT_TIMESTAMP) / 15.0);
        WHEN v_row.part_interval = '30 mins' THEN
            v_current_partition_timestamp := date_trunc('hour', CURRENT_TIMESTAMP) + 
                '30min'::interval * floor(date_part('minute', CURRENT_TIMESTAMP) / 30.0);
        WHEN v_row.part_interval = '1 hour' THEN
            v_current_partition_timestamp := date_trunc('hour', CURRENT_TIMESTAMP);
         WHEN v_row.part_interval = '1 day' THEN
            v_current_partition_timestamp := date_trunc('day', CURRENT_TIMESTAMP);
        WHEN v_row.part_interval = '1 week' THEN
            v_current_partition_timestamp := date_trunc('week', CURRENT_TIMESTAMP);
        WHEN v_row.part_interval = '1 month' THEN
            v_current_partition_timestamp := date_trunc('month', CURRENT_TIMESTAMP);
        WHEN v_row.part_interval = '1 year' THEN
            v_current_partition_timestamp := date_trunc('year', CURRENT_TIMESTAMP);
    END CASE;

    v_last_partition_timestamp := to_timestamp(substring(v_row.last_partition from char_length(v_row.parent_table||'_p')+1), v_row.datetime_string);

    v_premade_count = EXTRACT('epoch' FROM (v_last_partition_timestamp - v_current_partition_timestamp)::interval) / EXTRACT('epoch' FROM v_row.part_interval::interval);
    RAISE NOTICE 'v_premade_count %', v_premade_count;
    -- If it's been longer than the parent table's destinated interval, make the next partition
--    RAISE NOTICE 'It''s been this long: %', (CURRENT_TIMESTAMP - v_current_partition_timestamp)::interval;

--    IF ((CURRENT_TIMESTAMP - v_current_partition_timestamp)::interval >= v_row.part_interval) THEN
    IF v_premade_count < v_row.premake THEN
        RAISE NOTICE 'Creating next partition';
        EXECUTE 'SELECT part.create_next_time_partition('||quote_literal(v_row.parent_table)||')';
    END IF;

    IF v_row.type = 'time-static' THEN
        EXECUTE 'SELECT part.create_time_function('||quote_literal(v_row.parent_table)||')';
    END IF;

END LOOP; -- end of main loop

END
$$;
