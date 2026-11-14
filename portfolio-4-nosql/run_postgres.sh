#!/usr/bin/env bash
# MIT 8103 - Portfolio 4: build the document model, export it, and run the JSONB version.
# Needs the Portfolio 2 database (laguna_care) with its generated data already loaded.
# Set PGHOST / PGUSER / PGPASSWORD first if needed.
set -euo pipefail
cd "$(dirname "$0")"
export PGDATABASE=laguna_care
mkdir -p data sample_documents results
psql -X -q -f 01_build_documents.sql 2>/dev/null
psql -X -q -f 02_export_for_mongodb.sql
echo "Exported: $(wc -l < data/patients.json) patients, $(wc -l < data/encounters.json) encounters to data/"
psql -X -f 03_jsonb_document_store.sql > results/jsonb_output.txt 2>&1
echo "JSONB results written to results/jsonb_output.txt"
