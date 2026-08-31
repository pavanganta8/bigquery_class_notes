"""
dag_gold_load.py                                                  (Composer)
Converted from: PGSQL PROJECT/Scrpit/dag_gold_load.py

Same PostgresOperator -> BigQueryInsertJobOperator conversion as
dag_bronze_prepare.py -- see that file's header for the full rationale.
"""

from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from datetime import datetime

with DAG(
    dag_id="gold_layer_load",
    start_date=datetime(2024, 1, 1),
    schedule_interval="0 23 * * *",
    catchup=False,
) as dag:

    run_gold_proc = BigQueryInsertJobOperator(
        task_id="run_gold_procedure",
        gcp_conn_id="google_cloud_default",
        configuration={
            "query": {
                "query": "CALL `your_gcp_project.gold.dwh_load_todays_data`();",
                "useLegacySql": False,
            }
        },
    )
