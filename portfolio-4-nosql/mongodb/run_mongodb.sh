#!/usr/bin/env bash
# MIT 8103 - Portfolio 4: load the documents into MongoDB and run the queries.
# Needs MongoDB 5.0+ running on localhost:27017, plus mongoimport (MongoDB Database Tools) and mongosh.
# Run run_postgres.sh first: it creates data/patients.json and data/encounters.json.
# For MongoDB Atlas instead of a local server: export MONGO_URI="mongodb+srv://USER:PASS@cluster.../laguna_care"
set -euo pipefail
cd "$(dirname "$0")/.."
URI="${MONGO_URI:-mongodb://localhost:27017/laguna_care}"
mkdir -p results

mongoimport --uri "$URI" --collection patients   --drop --file data/patients.json
mongoimport --uri "$URI" --collection encounters --drop --file data/encounters.json
mongosh "$URI" --quiet mongodb/01_prepare.js | tee results/mongodb_prepare_output.txt
mongosh "$URI" --quiet mongodb/02_queries.js | tee results/mongodb_output.txt
