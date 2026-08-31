"""
dag_gcs_to_bronze.py                                              (Composer)
Converted from: PGSQL PROJECT/Scrpit/dag_minio_to_bronze.py

This is the most structurally different conversion in the project, because
the source system itself changes:

    PostgreSQL + self-hosted MinIO                BigQuery + GCS
    --------------------------------------------------------------------------
    A PythonOperator ran hand-written code          The GCS bucket IS the
    (minio-py client + psycopg2) to pull each        landing zone (see
    file out of MinIO and COPY it into Postgres      ../../gcs_load/README.md
    row by row via `cur.copy_expert(...)`.           for the crm/erp folder
                                                      layout). Loading is a
                                                      single declarative
                                                      GCSToBigQueryOperator
                                                      task per file -- no
                                                      custom Python, no
                                                      manual DB connection
                                                      handling, no temp files.

Each entry in the `files` dict from the original script becomes one
GCSToBigQueryOperator task below (crm/ and erp/ "buckets" become subfolders
of one GCS bucket, matching this repo's datasets/source_crm,
datasets/source_erp layout).
"""

from airflow import DAG
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import GCSToBigQueryOperator
from datetime import datetime

BUCKET = "your-bucket"
DATASET = "bronze"

# file -> (gcs_object, destination_table) -- mirrors the `files` dict from
# the original dag_minio_to_bronze.py, just with a GCS path instead of a
# (minio_bucket, object_name) pair.
FILES = {
    "load_crm_cust_info": ("datasets/source_crm/cust_info.csv", "crm_cust_info"),
    "load_crm_prd_info": ("datasets/source_crm/prd_info.csv", "crm_prd_info"),
    "load_crm_sales_details": ("datasets/source_crm/sales_details.csv", "crm_sales_details"),
    "load_erp_loc_a101": ("datasets/source_erp/LOC_A101.csv", "erp_loc_a101"),
    "load_erp_px_cat_g1v2": ("datasets/source_erp/PX_CAT_G1V2.csv", "erp_px_cat_g1v2"),
    "load_erp_cust_az12": ("datasets/source_erp/CUST_AZ12.csv", "erp_cust_az12"),
}

with DAG(
    dag_id="gcs_to_bronze",
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 23 * * *",
    catchup=False,
) as dag:

    for task_id, (object_path, table_name) in FILES.items():
        GCSToBigQueryOperator(
            task_id=task_id,
            bucket=BUCKET,
            source_objects=[object_path],
            destination_project_dataset_table=f"{DATASET}.{table_name}",
            source_format="CSV",
            skip_leading_rows=1,
            write_disposition="WRITE_TRUNCATE",  # replaces TRUNCATE + COPY
            create_disposition="CREATE_NEVER",   # tables already exist (ddl_bronze.sql)
            gcp_conn_id="google_cloud_default",
        )

# Note: unlike the MinIO version, there is no separate psycopg2 connection
# or temp-file handling to write -- GCSToBigQueryOperator is a managed
# BigQuery load job under the hood (the same mechanism as `bq load` / the
# `LOAD DATA` SQL statement in ../../gcs_load/).
