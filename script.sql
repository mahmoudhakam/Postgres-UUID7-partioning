create or replace function trials.uuid_generate_v7() returns uuid
as $$
  -- use random v4 uuid as starting point (which has the same variant we need)
  -- then overlay timestamp
  -- then set version 7 by flipping the 2 and 1 bit in the version 4 string
select encode(
  set_bit(
    set_bit(
      overlay(
        uuid_send(gen_random_uuid())
        placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
        from 1 for 6
      ),
      52, 1
    ),
    53, 1
  ),
  'hex')::uuid;
$$ language SQL volatile;
---------------
create extension pgcrypto  schema trials;
-------------
create or replace function trials.ts_to_uuid_v7(timestamptz) returns uuid
as $$
  select encode(
    set_bit(
      set_bit(
        overlay(
          uuid_send(gen_random_uuid())
          placing substring(int8send(floor(extract(epoch from $1) * 1000)::bigint) from 3)
          from 1 for 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex')::uuid;
$$ language SQL volatile;
---------------
create or replace function trials.uuid_v7_to_ts(uuid_v7 uuid) returns timestamptz
as $$
  select
    to_timestamp(
      (
        'x' || substring(
          encode(uuid_send(uuid_v7), 'hex')
          from 1 for 12
        )
      )::bit(48)::bigint / 1000.0
    )::timestamptz;
$$ language sql;
-----------------
select now(), trials.ts_to_uuid_v7(now() - interval '1y');
 -- 2024-02-18 20:05:55.544 +0200	018665b4-39d8-7cd2-9d6f-aa4cba999c47
select trials.uuid_v7_to_ts('018665b4-39d8-7cd2-9d6f-aa4cba999c47');

-----------------
CREATE TABLE trials.uuidv7_partitioning (
  id uuid NOT NULL ,
  payload text,
  uuid_ts timestamptz NOT NULL DEFAULT clock_timestamp() -- or now(), depending on goals
) PARTITION BY RANGE (uuid_ts);

drop table trials.uuidv7_partitioning;

select trials.ts_to_uuid_v7(now());
select now() ; -- 2024-02-18 20:28:30.733 +0200
select  clock_timestamp(); --2024-02-18 20:28:18.179 +0200


----------trials.uuidv7_partitioning

--Now, use TimescaleDB partitioning:

--create extension timescaledb;
--
--select create_hypertable(
--  relation := 'my_table',
--  time_column_name := 'uuid_ts',
--  -- !! very small interval is just for testing
--  chunk_time_interval := '1 minute'::interval
--);

SELECT version();

------------
-- Create partitions based on uuid_ts with one-minute intervals

CREATE TABLE trials.tbl_2022_01_01_01_tbl PARTITION OF trials.uuidv7_partitioning
  FOR VALUES FROM (TIMESTAMP '2022-01-01 00:01:00') TO (TIMESTAMP '2022-01-01 00:02:00');
 
CREATE TABLE trials.tbl_2022_01_01_02_tbl PARTITION OF trials.uuidv7_partitioning
  FOR VALUES FROM (TIMESTAMP '2022-01-01 00:02:00') TO (TIMESTAMP '2022-01-01 00:03:00');
 
CREATE TABLE trials.tbl_2022_01_01_03_tbl PARTITION OF trials.uuidv7_partitioning
  FOR VALUES FROM (TIMESTAMP '2022-01-01 00:03:00') TO (TIMESTAMP '2022-01-01 00:04:00');
 
 CREATE TABLE trials.tbl_2022_01_01_04_tbl PARTITION OF trials.uuidv7_partitioning
  FOR VALUES FROM (TIMESTAMP '2022-01-01 00:04:00') TO (TIMESTAMP '2022-01-01 00:05:00');
 
 CREATE TABLE trials.tbl_2022_01_01_05_tbl PARTITION OF trials.uuidv7_partitioning
  FOR VALUES FROM (TIMESTAMP '2022-01-01 00:05:00') TO (TIMESTAMP '2022-01-01 00:06:00');
 --------------------------------------------------------------------------------------------

INSERT INTO trials.uuidv7_partitioning (id, payload, uuid_ts)
SELECT
    -- Use the series for generating the id column
    trials.ts_to_uuid_v7(series.ts) as id,
    random()::text as payload,
    series.ts as uuid_ts
FROM generate_series(
    timestamptz '2022-01-01 00:01:00',
    timestamptz '2022-01-01 00:05:00',
    interval '30 second'
) as series(ts);

commit;
vacuum analyze trials.uuidv7_partitioning;

select id, uuid_ts  , (select trials.uuid_v7_to_ts(id)) from trials.uuidv7_partitioning;

select * from  trials.uuidv7_partitioning;
--drop table trials.uuidv7_partitioing ;

explain analyze select * from trials.uuidv7_partitioning where uuid_ts = trials.uuid_v7_to_ts('017e1282-a960-7c75-8044-85b6106dc4bb');
