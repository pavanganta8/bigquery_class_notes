#!/usr/bin/env bash
# =============================================================================
# gcs_load_cmds.sh -- GCS -> bronze load commands
# Converted from: PGSQL PROJECT/Scrpit/copy cmd.txt
# =============================================================================
# Original PostgreSQL workflow:
#   psql "postgresql://[username]:[password]@localhost:5432/[database_name]"
#   TRUNCATE TABLE BRONZE.CRM_CUST_INFO;
#   \copy BRONZE.CRM_CUST_INFO FROM 'C:\...\cust_info.csv' WITH (FORMAT csv, HEADER true, QUOTE '"');
#
# BigQuery has no interactive client session and no local-file \copy -- the
# CSVs must already be sitting in GCS (see ../../gcs_load/README.md for the
# upload step), and `bq load` (or the `LOAD DATA` SQL statement) pulls them
# in from there. TRUNCATE + \copy collapses into a single `bq load --replace`
# call per table.
# =============================================================================

set -euo pipefail

PROJECT="your-gcp-project"
BUCKET="your-bucket"
GCS_PREFIX="gs://${BUCKET}/BIGQUERY_PROJECT"

# One-time upload of this folder's CSVs (skip if already uploaded)
gsutil -m cp \
  "CUST_AZ12.csv" "LOC_A101.csv" "PX_CAT_G1V2.csv" \
  "cust_info.csv" "prd_info.csv" "sales_details.csv" \
  "${GCS_PREFIX}/"

# CRM CUSTOMER INFO
bq load --project_id="${PROJECT}" --replace --source_format=CSV \
  --skip_leading_rows=1 --quote='"' \
  bronze.crm_cust_info "${GCS_PREFIX}/cust_info.csv"

# CRM PRODUCT INFO
bq load --project_id="${PROJECT}" --replace --source_format=CSV \
  --skip_leading_rows=1 --quote='"' \
  bronze.crm_prd_info "${GCS_PREFIX}/prd_info.csv"

# CRM SALES DETAILS
bq load --project_id="${PROJECT}" --replace --source_format=CSV \
  --skip_leading_rows=1 --quote='"' \
  bronze.crm_sales_details "${GCS_PREFIX}/sales_details.csv"

# ERP LOC A101
bq load --project_id="${PROJECT}" --replace --source_format=CSV \
  --skip_leading_rows=1 --quote='"' \
  bronze.erp_loc_a101 "${GCS_PREFIX}/LOC_A101.csv"

# ERP PX CAT G1V2
bq load --project_id="${PROJECT}" --replace --source_format=CSV \
  --skip_leading_rows=1 --quote='"' \
  bronze.erp_px_cat_g1v2 "${GCS_PREFIX}/PX_CAT_G1V2.csv"

# ERP CUSTOMER AZ12
bq load --project_id="${PROJECT}" --replace --source_format=CSV \
  --skip_leading_rows=1 --quote='"' \
  bronze.erp_cust_az12 "${GCS_PREFIX}/CUST_AZ12.csv"

echo "Bronze layer loaded from ${GCS_PREFIX}/"
