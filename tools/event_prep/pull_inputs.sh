#!/usr/bin/env bash
# Pull the monitoring product from CCMMF S3 into the layout the step3_* scripts expect.
#
#   ./pull_inputs.sh --list     show every version available per product, then exit
#   ./pull_inputs.sh            pull the pinned versions for the default parcels
#   ./pull_inputs.sh 565118 590073
#
# Versions are pinned, not "latest", because the products are not drop-in compatible
# across major versions. See the README.

set -euo pipefail

S3_ENDPOINT=${S3_ENDPOINT:-https://s3.garage.ccmmf.ncsa.cloud}
S3_BUCKET=${S3_BUCKET:-carb}
export AWS_PROFILE=${AWS_PROFILE:-ccmmf-garage}

# Same chain as setup_env.sh, so this and the R scripts agree without extra config.
CCMMF_BASE=${CCMMF_BASE:-$HOME}
CCMMF_ROOT=${CCMMF_ROOT:-$CCMMF_BASE/ccmmf}
PRODUCTS_ROOT=${PRODUCTS_ROOT:-$CCMMF_ROOT/products}
PRODUCTS_INVENTORY=${PRODUCTS_INVENTORY:-$PRODUCTS_ROOT/inventory}
EVENT_OUTPUT_DIR=${EVENT_OUTPUT_DIR:-$PRODUCTS_INVENTORY/event_files}
CCMMF_WORK=${CCMMF_WORK:-$CCMMF_ROOT/work}

# Pinned versions: these are the ones that reproduce the committed runs/*/events.json.
PLANTING_VERSION=${PLANTING_VERSION:-v1.0}
HARVEST_VERSION=${HARVEST_VERSION:-v1.0}
IRRIGATION_VERSION=${IRRIGATION_VERSION:-v1.1}
FERTILIZATION_VERSION=${FERTILIZATION_VERSION:-v1.0}

s3() { aws --endpoint-url "$S3_ENDPOINT" s3 "$@"; }
say() { printf '  %s\n' "$*"; }

if [ "${1:-}" = "--list" ]; then
  for p in planting harvest irrigation tillage fertilization; do
    printf '%s:\n' "$p"
    s3 ls "s3://$S3_BUCKET/management/$p/" | sed 's/^/  /'
  done
  cat <<'EOF'

Pinned by this script: planting v1.0, harvest v1.0, irrigation v1.1,
fertilization v1.0. A newer version is not automatically a drop-in replacement
-- fertilization v2.0 changes both the event dates and the N speciation. Only
move the pin after re-running the step3 scripts and diffing runs/*/events.json.
EOF
  exit 0
fi

PARCELS=("$@")
[ ${#PARCELS[@]} -eq 0 ] && PARCELS=(565118 328163 590073)   # US-Bi2, US-Bi1, US-Twt

MGMT="$PRODUCTS_INVENTORY/management"
mkdir -p "$MGMT" "$EVENT_OUTPUT_DIR" "$CCMMF_WORK"

say "endpoint  $S3_ENDPOINT (bucket $S3_BUCKET, profile $AWS_PROFILE)"
say "target    $PRODUCTS_INVENTORY"
say "parcels   ${PARCELS[*]}"
echo

# --- statewide per-year products -------------------------------------------
# Small enough to take whole; the step3 scripts need several years each.
for spec in "planting:$PLANTING_VERSION" "harvest:$HARVEST_VERSION" "tillage:v1.0"; do
  p=${spec%%:*}; v=${spec##*:}
  say "$p $v -> $MGMT/$p/$v"
  s3 sync "s3://$S3_BUCKET/management/$p/$v/" "$MGMT/$p/$v/" --only-show-errors
done

# --- fertilization ----------------------------------------------------------
# Hive-partitioned by event_member_id. The R scripts open it as a dataset at
# $EVENT_OUTPUT_DIR/fertilization.parquet, so land it under exactly that name.
say "fertilization $FERTILIZATION_VERSION -> $EVENT_OUTPUT_DIR/fertilization.parquet"
s3 sync "s3://$S3_BUCKET/management/fertilization/$FERTILIZATION_VERSION/" \
        "$EVENT_OUTPUT_DIR/fertilization.parquet/" --only-show-errors

# --- irrigation -------------------------------------------------------------
# 121 shards, ~4 GB in total, so pull only the shards that can hold our parcels.
# Shard names are NOMINAL ranges and they overlap; a parcel inside a shard's
# named range is not necessarily in that shard. Take every shard whose range
# covers the parcel and let the reader filter.
say "irrigation $IRRIGATION_VERSION -> $MGMT/irrigation/$IRRIGATION_VERSION (matching shards only)"
mkdir -p "$MGMT/irrigation/$IRRIGATION_VERSION"
shards=$(s3 ls "s3://$S3_BUCKET/management/irrigation/$IRRIGATION_VERSION/" \
         | awk '{print $4}' | grep -E '^[0-9]+_[0-9]+\.parquet$' || true)
for f in $shards; do
  lo=${f%%_*}; hi=${f#*_}; hi=${hi%.parquet}
  for parcel in "${PARCELS[@]}"; do
    if [ "$lo" -le "$parcel" ] && [ "$parcel" -le "$hi" ]; then
      s3 cp "s3://$S3_BUCKET/management/irrigation/$IRRIGATION_VERSION/$f" \
            "$MGMT/irrigation/$IRRIGATION_VERSION/$f" --only-show-errors
      say "  shard $f (covers $parcel)"
      break
    fi
  done
done

echo
say "done. next: extract_parcel_csvs.R to build the per-parcel CSVs, e.g."
say "  Rscript extract_parcel_csvs.R us_bi2 565118"
