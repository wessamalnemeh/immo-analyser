#!/usr/bin/env bash
# True mirror-sync of ./workflows into n8n: creates/updates workflows from
# local JSON files (same as `n8n import:workflow` always did), AND deletes
# any workflow in n8n whose local file was removed -- which the plain
# import command never does on its own, since it only ever adds/overwrites.
#
# Requires: curl, jq (on the host running this script -- `brew install jq`
# on macOS if you don't have it), and an n8n API key in .env.
# Create the key in n8n: Settings -> n8n API -> Create an API Key.

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env found. Copy .env.example to .env first." >&2
  exit 1
fi
set -a; source .env; set +a

N8N_URL="${N8N_URL:-http://localhost:5678}"

if [ -z "${N8N_API_KEY:-}" ]; then
  echo "N8N_API_KEY is not set in .env." >&2
  echo "Create one in n8n: Settings -> n8n API -> Create an API Key, then add it to .env as N8N_API_KEY=..." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed. On macOS: brew install jq" >&2
  exit 1
fi

echo "Fetching current workflow IDs from n8n..."
remote_ids=$(curl -sf -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows?limit=250" | jq -r '.data[].id')

echo "Reading local workflow IDs from ./workflows..."
local_ids=$(jq -r '.id' workflows/*.json)

deleted_any=false
for id in $remote_ids; do
  if ! grep -qx "$id" <<< "$local_ids"; then
    echo "  Deleting workflow no longer present locally: $id"
    curl -sf -X DELETE -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$id" > /dev/null
    deleted_any=true
  fi
done
if [ "$deleted_any" = false ]; then
  echo "  Nothing to delete -- every remote workflow still has a local file."
fi

echo "Importing/updating from local files..."
docker exec -it n8n n8n import:workflow --separate --input=/workflows

echo "Sync complete."
