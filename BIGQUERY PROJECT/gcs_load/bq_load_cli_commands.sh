#!/usr/bin/env bash
# =============================================================================
# bq load CLI commands: GCS -> bronze                              (BigQuery)
# =============================================================================
# BigQuery equivalent of `PGSQL PROJECT/Scrpit/copy cmd.txt`
# (psql "postgresql://user:pass@host:5432/db" + \copy ... FROM 'local file').
#
# There is no interactive shell session to open first (no psql equivalent) --
# `bq` is a stateless CLI, so every command below is self-contained. Set
# PROJECT/BUCKET once, then run.
# =============================================================================

set -euo pipefail

PROJECT="your-gcp-project"
BUCKET="your-bucket"

# Upload local CSVs to GCS once (skip if the files are already in the bucket).
gsutil -m cp -r "datasets/source_crm" "gs://${BUCKET}/datasets/"
gsutil -m cp -r "datasets/source_erp" "gs://${BUCKET}/datasets/"

# CRM CUSTOMER INFO
bq load --project_id="${PROJECT}" --replace --source_format=CSV --skip_leading_rows=1 \
  bronze.crm_cust_info \
  "gs://${BUCKET}/datasets/source_crm/cust_info.csv"

# CRM PRODUCT INFO
bq load --project_id="${PROJECT}" --replace --source_format=CSV --skip_leading_rows=1 \
  bronze.crm_prd_info \
  "gs://${BUCKET}/datasets/source_crm/prd_info.csv"

# CRM SALES DETAILS
bq load --project_id="${PROJECT}" --replace --source_format=CSV --skip_leading_rows=1 \
  bronze.crm_sales_details \
  "gs://${BUCKET}/datasets/source_crm/sales_details.csv"

# ERP LOC A101
bq load --project_id="${PROJECT}" --replace --source_format=CSV --skip_leading_rows=1 \
  bronze.erp_loc_a101 \
  "gs://${BUCKET}/datasets/source_erp/LOC_A101.csv"

# ERP CUSTOMER AZ12
bq load --project_id="${PROJECT}" --replace --source_format=CSV --skip_leading_rows=1 \
  bronze.erp_cust_az12 \
  "gs://${BUCKET}/datasets/source_erp/CUST_AZ12.csv"

# ERP PX CAT G1V2
bq load --project_id="${PROJECT}" --replace --source_format=CSV --skip_leading_rows=1 \
  bronze.erp_px_cat_g1v2 \
  "gs://${BUCKET}/datasets/source_erp/PX_CAT_G1V2.csv"

echo "Bronze layer loaded from gs://${BUCKET}/datasets/"
