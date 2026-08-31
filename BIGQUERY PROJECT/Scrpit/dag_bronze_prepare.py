"""
dag_bronze_prepare.py                                            (Composer)
Converted from: PGSQL PROJECT/Scrpit/dag_bronze_prepare.py

PostgreSQL -> BigQuery / Composer notes:
    - airflow.providers.postgres.operators.postgres.PostgresOperator
        -> airflow.providers.google.cloud.operators.bigquery.BigQueryInsertJobOperator
    - postgres_conn_id="postgres_local"
        -> gcp_conn_id="google_cloud_default" (or your configured Composer
           connection to the target GCP project)
    - sql="CALL bronze.dwh_load_crm_erp_bronze();"
        -> same CALL statement, just wrapped in the job "query" config below,
           with useLegacySql explicitly disabled (BigQuery scripting/
           procedures require Standard SQL).
"""

from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from datetime import datetime

with DAG(
    dag_id="bronze_prepare_tables",
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 23 * * *",
    catchup=False,
) as dag:

    run_bronze_proc = BigQueryInsertJobOperator(
        task_id="run_bronze_procedure",
        gcp_conn_id="google_cloud_default",
        configuration={
            "query": {
                "query": "CALL `your_gcp_project.bronze.dwh_load_crm_erp_bronze`();",
                "useLegacySql": False,
            }
        },
    )
