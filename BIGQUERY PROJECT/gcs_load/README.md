# GCS -> BigQuery landing layer

PostgreSQL read the CSVs straight off local/server disk with `COPY ... FROM
'C:\...'`. BigQuery cannot do that — the files first have to land in a
**Google Cloud Storage (GCS) bucket**, then get loaded into the `bronze`
dataset from there. This folder documents that hand-off.

## 1. Bucket / folder layout

Mirror the `datasets/` folder from this repo inside one GCS bucket:

```
gs://your-bucket/
└── datasets/
    ├── source_crm/
    │   ├── cust_info.csv
    │   ├── prd_info.csv
    │   └── sales_details.csv
    └── source_erp/
        ├── CUST_AZ12.csv
        ├── LOC_A101.csv
        └── PX_CAT_G1V2.csv
```

Upload once (or let a Composer/Airflow task do it as part of the pipeline):

```bash
gsutil -m cp -r "datasets/source_crm" "gs://your-bucket/datasets/"
gsutil -m cp -r "datasets/source_erp" "gs://your-bucket/datasets/"
```

## 2. Two ways to load GCS -> bronze

1. **`LOAD DATA` DDL statement** — runs *inside* BigQuery SQL/scripting, so it
   is what `bronze/proc_load_bronze.sql` uses. See
   [`load_data_gcs_to_bronze.sql`](load_data_gcs_to_bronze.sql).
2. **`bq load` CLI** — the direct replacement for the old
   `PGSQL PROJECT/Scrpit/copy cmd.txt` (`\copy ... FROM 'local path'`)
   workflow, useful for ad-hoc/manual loads or a Composer `BashOperator`. See
   [`bq_load_cli_commands.sh`](bq_load_cli_commands.sh).

Airflow/Composer normally uses neither directly — it calls the **procedure**
(`CALL bronze.load_bronze()`) via `BigQueryInsertJobOperator`, or loads files
with the dedicated `GCSToBigQueryOperator`. Both patterns are shown in
`../BIGQUERY PROJECT/Scrpit/dag_gcs_to_bronze.py`.

## 3. PostgreSQL -> BigQuery mapping for this step

| PostgreSQL                                              | BigQuery                                                        |
|-----------------------------------------------------------|-------------------------------------------------------------------|
| `COPY table FROM 'C:\local\file.csv' WITH (FORMAT csv, HEADER true);` | `LOAD DATA OVERWRITE dataset.table FROM FILES (format='CSV', skip_leading_rows=1, uris=['gs://bucket/path/*.csv']);` |
| `psql \copy ...` (client-side copy)                      | `bq load --source_format=CSV --skip_leading_rows=1 dataset.table gs://bucket/path/file.csv schema.json` |
| Local filesystem path                                    | GCS URI (`gs://...`) — BigQuery only reads from GCS, Drive, or inline data, never local disk |
| Server needing filesystem read permission                | Service account needing `roles/storage.objectViewer` on the bucket and `roles/bigquery.dataEditor` on the dataset |
