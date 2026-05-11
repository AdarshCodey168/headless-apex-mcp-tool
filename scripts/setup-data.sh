#!/bin/bash

# Loads all sample data into the target org using sf data import tree.
# Patches the Standard Pricebook ID into JSON files before import.
#
# Usage: ./scripts/setup-data.sh [target-org-alias]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$PROJECT_DIR/data"
TEMP_DIR="$PROJECT_DIR/data/.tmp"

ORG=${1:-}
ORG_FLAG=""
if [ -n "$ORG" ]; then
  ORG_FLAG="--target-org $ORG"
fi

# Clean up temp dir on exit
trap "rm -rf $TEMP_DIR" EXIT
mkdir -p "$TEMP_DIR"

echo "=== Step 1: Query Standard Pricebook ID ==="
STANDARD_PB_ID=$(sf data query $ORG_FLAG \
  --query "SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1" \
  --result-format json | jq -r '.result.records[0].Id')

if [ -z "$STANDARD_PB_ID" ] || [ "$STANDARD_PB_ID" = "null" ]; then
  echo "ERROR: Could not find Standard Pricebook. Ensure your org has one."
  exit 1
fi
echo "Standard Pricebook ID: $STANDARD_PB_ID"

echo ""
echo "=== Step 2: Activate Standard Pricebook ==="
sf data update record $ORG_FLAG \
  --sobject Pricebook2 \
  --record-id "$STANDARD_PB_ID" \
  --values "IsActive=true"
echo "Done."

echo ""
echo "=== Step 3: Prepare data files ==="
# Copy all JSON files to temp, replacing the placeholder with the real ID
for file in "$DATA_DIR"/*.json; do
  sed "s/__STANDARD_PRICEBOOK_ID__/$STANDARD_PB_ID/g" "$file" > "$TEMP_DIR/$(basename "$file")"
done
echo "Patched JSON files written to temp directory."

echo ""
echo "=== Step 4: Import data ==="
sf data import tree $ORG_FLAG --plan "$TEMP_DIR/data-plan.json"

echo ""
echo "=== Done! ==="
echo "Sample data loaded successfully."
echo ""
echo "Test with:"
echo "  Account: 'Acme Corporation' (3 open deals, \$315K pipeline)"
echo "  Account: 'Globox Industries' (2 open deals, \$575K pipeline)"
