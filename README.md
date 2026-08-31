# PostgreSQL -> BigQuery conversion
-- this is a feature brANCH FOR CHANGES
Everything in `pgsql/` converted to BigQuery, folder-for-folder and
file-for-file, keeping the same names so you can diff any file here against
its PostgreSQL original side by side.

## Folder map

| Folder | Mirrors (pgsql) | What it is |
|---|---|---|
| [`datasets/`](datasets/) | `datasets/` | Raw source CSVs (`source_crm/`, `source_erp/`) — upload these to a GCS bucket, see `gcs_load/README.md`. |
| [`gcs_load/`](gcs_load/) | *(new — no PG equivalent)* | The GCS landing step PostgreSQL didn't need: bucket layout, `LOAD DATA` SQL, `bq load` CLI commands. |
| [`bronze/`](bronze/) | `bronze/` | Raw-layer DDL + `load_bronze()` procedure (GCS → bronze via `LOAD DATA`). |
| [`silver/`](silver/) | `silver/` | Cleansed-layer DDL + `load_silver()` procedure (bronze → silver). |
| [`gold/`](gold/) | `gold/` | Star-schema DDL + `load_gold()` procedure (silver → gold). |
| [`procedure_bigquery/`](procedure_bigquery/) | `procedure_pgsql/` | Procedure-language tutorial notes, topic by topic (variables, if/else, loops, exceptions, cursors, functions, triggers) + a mini end-to-end project. |
| [`BIGQUERY PROJECT/`](BIGQUERY%20PROJECT/) | `PGSQL PROJECT/` | The full worked project: DDL, load procedures, GCS load commands, and the 5 Cloud Composer DAGs that schedule it all. |

## The pipeline, end to end

```
 datasets/source_crm, datasets/source_erp   (local CSVs, or BIGQUERY PROJECT/*.csv)
              │  gsutil cp / Composer upload task
              ▼
 gs://your-bucket/datasets/...              (GCS landing zone — gcs_load/)
              │  LOAD DATA / bq load / GCSToBigQueryOperator
              ▼
 bronze.*  (raw, untyped-ish landing tables — bronze/ddl_bronze.sql)
              │  CALL bronze.load_bronze()  /  CALL bronze.dwh_load_crm_erp_bronze()
              ▼
 silver.* (cleaned, typed, deduplicated — silver/ddl_silver.sql)
              │  CALL silver.load_silver()  /  CALL silver.dwh_data_load_silver()
              ▼
 gold.*   (star schema: dim_customers, dim_products, fact_sales — gold/ddl_gold.sql)
              │  CALL gold.load_gold()  /  CALL gold.dwh_load_todays_data()
              ▼
        BI / reporting layer (Looker Studio, Looker, etc.)
```

Every arrow above is one task in **Cloud Composer** (managed Airflow) — see
`BIGQUERY PROJECT/Scrpit/dag_gcs_to_bronze.py`, `dag_bronze_prepare.py`,
`dag_silver_load.py`, `dag_gold_load.py`. Each DAG calls a BigQuery
**procedure** through `BigQueryInsertJobOperator`, the same way the original
PostgreSQL DAGs called procedures through `PostgresOperator`.

## Two ways to run this

1. **Console/`bq query`, following `procedure_bigquery/project/04_run_project.sql`'s
   numbered steps** — good for learning the concepts interactively.
2. **Composer**, using the DAGs in `BIGQUERY PROJECT/Scrpit/` — good for the
   real scheduled pipeline. Copy those `.py` files into your Composer
   environment's `dags/` GCS folder; Airflow picks them up automatically.
   (The original `airflow_dags_11pm_pipeline.zip` bundle is superseded by
   these plain `.py` files — Composer syncs a `dags/` folder directly, it
   doesn't need a zip.)

## Setup you only do once

```bash
# 1. Create the three datasets (BigQuery's equivalent of PostgreSQL schemas)
bq mk --dataset --location=US your_gcp_project:bronze
bq mk --dataset --location=US your_gcp_project:silver
bq mk --dataset --location=US your_gcp_project:gold
bq mk --dataset --location=US your_gcp_project:audit   # used by procedure_bigquery/project/

# 2. Upload the source CSVs to GCS
gsutil -m cp -r datasets/source_crm gs://your-bucket/datasets/
gsutil -m cp -r datasets/source_erp gs://your-bucket/datasets/

# 3. Run the DDL, then the load procedures, in order:
#    bronze/ddl_bronze.sql -> silver/ddl_silver.sql -> gold/ddl_gold.sql
#    CALL bronze.load_bronze(); CALL silver.load_silver(); CALL gold.load_gold();
```

Every file with `gs://your-bucket` or `your_gcp_project` in it needs those
placeholders swapped for your real bucket/project before it will run.

## PostgreSQL -> BigQuery cheat sheet

The single reference table for every substitution used across this folder —
each concept is demonstrated live in `procedure_bigquery/`.

| PostgreSQL (PL/pgSQL) | BigQuery (BigQuery scripting / Standard SQL) | Where it's used |
|---|---|---|
| `CREATE PROCEDURE ... LANGUAGE plpgsql AS $$ ... $$;` | `CREATE PROCEDURE ... BEGIN ... END;` | every `.sql` file |
| `schema` | `dataset` (created out-of-band with `bq mk --dataset`, never in SQL) | all DDL |
| `INT` / `INTEGER` | `INT64` | all DDL |
| `VARCHAR(n)` / `TEXT` / `CHAR(1)` | `STRING` | all DDL |
| `BOOLEAN` | `BOOL` | `procedure_bigquery/project/01_ddl.sql` |
| `SERIAL` / auto-increment | no equivalent — `ROW_NUMBER()` for sequential surrogate keys, `GENERATE_UUID()` for opaque IDs | `gold/proc_load_gold.sql`, `procedure_bigquery/project/` |
| `DECLARE x TYPE := val;` | `DECLARE x TYPE DEFAULT val;` | `procedure_bigquery/01_variables_and_datatypes.sql` |
| `x := val;` | `SET x = val;` | everywhere |
| `%TYPE` anchored types | not supported — spell the type out | `01_variables_and_datatypes.sql` |
| `RECORD` variable | loop variable is implicitly a `STRUCT` | `01_variables_and_datatypes.sql`, `03_for_loop.sql` |
| `RAISE NOTICE '...', x;` | `SELECT FORMAT('...', x) AS log_message;` (or write to an audit table for durable logs) | everywhere |
| `ELSIF` | `ELSEIF` | `02_if_else_control.sql` |
| `FOR i IN 1..5 LOOP` | `FOR r IN (SELECT i FROM UNNEST(GENERATE_ARRAY(1,5)) AS i) DO` | `03_for_loop.sql` |
| `FOR i IN REVERSE 5..1` | `GENERATE_ARRAY(5,1,-1)` | `03_for_loop.sql` |
| `EXIT` / `CONTINUE` (optionally `EXIT label`) | `LEAVE` / `ITERATE` (optionally `LEAVE label`) | `03_for_loop.sql`, `04_while_loop.sql` |
| `EXIT WHEN cond;` | `IF cond THEN LEAVE; END IF;` | `04_while_loop.sql` |
| `EXCEPTION WHEN division_by_zero / unique_violation / ... THEN` | `EXCEPTION WHEN ERROR THEN` (one catch-all; branch on `@@error.message` text if needed) | `05_exception_handling_basic.sql` |
| `SQLERRM` / `SQLSTATE` | `@@error.message` / `@@error.formatted_stack_trace` | `05_..._basic.sql`, `07_..._advanced.sql` |
| `RAISE EXCEPTION 'msg' USING ERRCODE=.., DETAIL=.., HINT=..;` | `RAISE USING MESSAGE = 'msg';` (fold detail/hint into the message text) | `07_exception_handling_advanced.sql` |
| `GET STACKED DIAGNOSTICS v = MESSAGE_TEXT, ...;` | read `@@error.*` directly, no separate step | `07_exception_handling_advanced.sql` |
| **Cursors** (`DECLARE ... CURSOR`, `OPEN`/`FETCH`/`CLOSE`) | **not supported at all** — rewrite as a set-based `JOIN` (+ optional `TEMP TABLE` staging) | `06_cursors.sql`, `project/proc_load_fact_sales.sql` |
| `CREATE FUNCTION ... LANGUAGE plpgsql AS $$ DECLARE...BEGIN...END $$;` | SQL UDF body must be **one expression** — rewrite procedural logic as `CASE`, use `ERROR()` for validation | `08_functions.sql`, `project/func_*.sql` |
| Function `OUT`/`INOUT` params | not supported on functions — use a **procedure** instead (procedures do support `IN`/`OUT`/`INOUT`) | `08_functions.sql` |
| `RETURNS TABLE (...) ... RETURN QUERY SELECT ...;` | `CREATE TABLE FUNCTION ... AS (SELECT ...);` | `08_functions.sql` |
| Exception-based safe casting (`BEGIN CAST... EXCEPTION WHEN OTHERS RETURN 0 END;`) | `SAFE_CAST(...)`, `SAFE_DIVIDE(...)`, `SAFE.PARSE_DATE(...)` | `project/func_clean_price.sql`, `func_parse_date_safe.sql` |
| **Triggers** (`CREATE TRIGGER ... BEFORE/AFTER ... FOR EACH ROW`) | **not supported at all** — stamp/log inline in the same `UPDATE`/`MERGE`/procedure instead | `09_triggers.sql`, `project/trigger_update_timestamp.sql` |
| `COPY table FROM 'local/path.csv' WITH (FORMAT csv, HEADER true);` | `LOAD DATA OVERWRITE dataset.table FROM FILES (format='CSV', skip_leading_rows=1, uris=['gs://...']);` | `gcs_load/`, `bronze/proc_load_bronze.sql` |
| `psql \copy ...` (client-side) | `bq load --source_format=CSV ...` | `gcs_load/bq_load_cli_commands.sh`, `BIGQUERY PROJECT/Scrpit/gcs_load_cmds.sh` |
| `TO_DATE(x, 'YYYYMMDD')` | `PARSE_DATE('%Y%m%d', x)` | `silver/proc_load_silver.sql` |
| `SUBSTRING(x FROM a FOR b)` / `FROM a` | `SUBSTR(x, a, b)` / `SUBSTR(x, a)` | `silver/proc_load_silver.sql` |
| `SPLIT_PART(x, ' ', n)` | `SPLIT(x, ' ')[SAFE_OFFSET(n-1)]` (0-indexed) | `project/proc_load_dim_customer.sql` |
| `x ~ '^[0-9]+$'` | `REGEXP_CONTAINS(x, r'^[0-9]+$')` | `project/proc_load_dim_customer.sql` |
| `date_expr - INTERVAL '1 day'` | `DATE_SUB(date_expr, INTERVAL 1 DAY)` | `silver/proc_load_silver.sql` |
| `DATE_TRUNC('month', col)` | `DATE_TRUNC(col, MONTH)` (unit second, unquoted) | `gold/proc_load_gold.sql` |
| `clock_timestamp()` | `CURRENT_TIMESTAMP()` | everywhere |
| `EXTRACT(EPOCH FROM (t2 - t1))` | `TIMESTAMP_DIFF(t2, t1, SECOND)` | `bronze/`, `silver/`, `gold/` load procedures |
| `col::DATE` / `col::TEXT` casts | `CAST(col AS DATE)` / `CAST(col AS STRING)` | `silver_proc.sql` |
| `GET DIAGNOSTICS x = ROW_COUNT;` | `SET x = @@row_count;` (read right after the DML statement) | `project/proc_load_dim_customer.sql` |
| `EXECUTE 'sql' INTO var;` (dynamic SQL) | `EXECUTE IMMEDIATE 'sql' INTO var;` | `project/proc_validate_load.sql` |
| `DELETE FROM t;` (no WHERE needed) | `DELETE FROM t WHERE TRUE;` (BigQuery requires a WHERE clause) | `project/proc_load_dim_customer.sql` |
