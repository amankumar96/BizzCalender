#!/usr/bin/env bash
# Materializes the flat supabase/migrations/ folder the Supabase CLI actually reads,
# by combining core/*.sql with exactly one industry's migrations. Core files are
# numbered 0001-0010 and each industry reserves its own Nxxx block (wedding=1xxx,
# clinic=2xxx, ...), so copying both sets into one flat folder sorts in the right
# apply order without any renaming.
#
# Usage: scripts/materialize_tenant_migrations.sh <industry_folder_name>
# Example: scripts/materialize_tenant_migrations.sh wedding_photography
set -euo pipefail

INDUSTRY="${1:?usage: materialize_tenant_migrations.sh <industry_folder_name>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT/supabase/migrations/core"
INDUSTRY_DIR="$ROOT/supabase/migrations/industries/$INDUSTRY"
TARGET_DIR="$ROOT/supabase/migrations"

if [ ! -d "$INDUSTRY_DIR" ]; then
  echo "No such industry folder: $INDUSTRY_DIR" >&2
  exit 1
fi

# Clear out any previously materialized flat files (but never touch core/ or industries/).
find "$TARGET_DIR" -maxdepth 1 -name '*.sql' -type f -delete

cp "$CORE_DIR"/*.sql "$TARGET_DIR"/
cp "$INDUSTRY_DIR"/*.sql "$TARGET_DIR"/

count=$(find "$TARGET_DIR" -maxdepth 1 -name '*.sql' -type f | wc -l)
echo "Materialized $count migration files into $TARGET_DIR for industry '$INDUSTRY':"
find "$TARGET_DIR" -maxdepth 1 -name '*.sql' -type f -printf '%f\n' | sort
