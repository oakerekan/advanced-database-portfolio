#!/usr/bin/env bash
# MIT 8103 - Portfolio 5: stop every demo server and delete the cluster/ folder.
cd "$(dirname "$0")"
for d in cluster/replication/* cluster/sharding/*; do
  [ -f "$d/PG_VERSION" ] && pg_ctl -D "$d" -m fast -w stop >/dev/null 2>&1 && echo "stopped $d"
done
rm -rf cluster
echo "cluster/ removed"
