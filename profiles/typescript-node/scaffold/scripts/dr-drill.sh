#!/bin/sh
# DR backup/restore drill — PROVES disaster recovery works by actually restoring a backup into an
# ISOLATED scratch database and verifying integrity. It NEVER touches the source data. Aligns with
# NIST SP 800-34 and the kit's docs/continuity/backup-restore-drill.md.
#
# Records nothing by itself — read the printed RTO/RPO actuals into RUNBOOK §6.
#
# Usage:  sh scripts/dr-drill.sh
# Env:    DATABASE_URL (or standard PG vars: PGHOST/PGPORT/PGUSER/PGPASSWORD)
#         SRC_DB     — source database name      (default: app)
#         SCRATCH_DB — isolated restore target   (default: app_restore_drill)
#         TABLE      — table to integrity-check   (default: items)
#
# ADAPT: set TABLE (and the column list in CKSUM_SQL below) to a real data-bearing table of your
# schema. Keep the fail-closed guard and the null-safe checksum intact.
set -eu

SRC_DB="${SRC_DB:-app}"
SCRATCH_DB="${SCRATCH_DB:-app_restore_drill}"
TABLE="${TABLE:-items}"
DUMP="${DUMP:-/tmp/dr-drill.dump}"
fail=0

# If DATABASE_URL is set, derive PG* connection env from it so pg_dump/psql/pg_restore use one source
# of truth. (Standard PG env vars also work directly.) The DB NAME for each operation is passed via -d.
# NOTE: this URL parse uses GNU sed (the `;t` branch). On Linux CI/deploy that is the default; on a
# macOS/BSD dev box, set the standard PG* vars (PGHOST/PGPORT/PGUSER/PGPASSWORD) directly instead. The
# scratch/source DB NAMES never come from the URL (only -d flags), so the fail-closed guard is unaffected.
if [ -n "${DATABASE_URL:-}" ]; then
  export PGHOST="$(printf '%s' "$DATABASE_URL" | sed -E 's#^[a-z]+://([^:/@]+:[^@]*@)?([^:/?]+).*#\2#')"
  export PGPORT="$(printf '%s' "$DATABASE_URL" | sed -E 's#^[a-z]+://([^@]*@)?[^:/?]+:([0-9]+).*#\2#;t;s#.*#5432#')"
  export PGUSER="$(printf '%s' "$DATABASE_URL" | sed -E 's#^[a-z]+://([^:/@]+)(:[^@]*)?@.*#\1#;t;s#.*#postgres#')"
  PGPW="$(printf '%s' "$DATABASE_URL" | sed -E 's#^[a-z]+://[^:/@]+:([^@]*)@.*#\1#;t;s#.*##')"
  [ -n "$PGPW" ] && export PGPASSWORD="$PGPW"
fi

# ---- FAIL-CLOSED safety guard ----
# The drill may ONLY ever drop/create the scratch DB. Enforce (not just document) that the scratch
# target is neither the source nor any protected name — a single mis-set env var must never let
# `drop database` hit live data. Refuse to run otherwise.
[ "$SCRATCH_DB" = "$SRC_DB" ] && { echo "FATAL: SCRATCH_DB must differ from SRC_DB ($SRC_DB)"; exit 1; }
case "$SCRATCH_DB" in
  postgres|template0|template1|"")
    echo "FATAL: refusing to use protected/empty DB name as scratch: '$SCRATCH_DB'"; exit 1 ;;
esac
case "$SCRATCH_DB" in
  *_restore_drill) : ;;  # require the explicit drill suffix so scratch can't masquerade as a real DB
  *) echo "FATAL: SCRATCH_DB must end in '_restore_drill' (got '$SCRATCH_DB')"; exit 1 ;;
esac

q() { psql -tAc "$2" -d "$1"; }   # q <db> <sql> -> bare value

# Integrity checksum — defined ONCE so source and restored copy use the IDENTICAL expression.
# concat_ws() ignores NULLs PER ARGUMENT (a NULL in one column does not null the whole row), and
# coalesce() guards nullable columns — so this is null-safe and stays sensitive to corruption in any
# column. NOTE: bare `||` would yield NULL for the whole row if any column is NULL — do not use it.
# ADAPT the column list to your table's data-bearing columns.
CKSUM_SQL="select coalesce(md5(string_agg(concat_ws('|', id::text, coalesce(name,''), coalesce(created_at::text,'')), ',' order by id)), '') from \"$TABLE\""

echo "===== DR backup/restore drill ====="

# 1. RPO marker — the backup's data-loss window starts here.
BACKUP_TS=$(q "$SRC_DB" "select now()")
echo "1. Backup point (RPO marker): $BACKUP_TS"

# 2. Integrity baseline from the SOURCE (what a good restore must reproduce).
SRC_COUNT=$(q "$SRC_DB" "select count(*) from \"$TABLE\"")
SRC_CKSUM=$(q "$SRC_DB" "$CKSUM_SQL")
echo "2. Source baseline: rows=$SRC_COUNT content-checksum=$SRC_CKSUM"

# 3. Back up (custom format — the realistic managed-DB dump style; restores with pg_restore).
pg_dump -Fc -d "$SRC_DB" -f "$DUMP"
echo "3. Backup captured -> $DUMP (custom format)"

# 4. Isolated scratch DB — drop-if-exists then create. Guarded above to never be the source.
psql -d postgres -q -c "drop database if exists \"$SCRATCH_DB\""
psql -d postgres -q -c "create database \"$SCRATCH_DB\""
echo "4. Isolated scratch DB created: $SCRATCH_DB"

# 5. Restore — measure RTO actual (wall-clock to a usable DB).
START=$(date +%s)
pg_restore -d "$SCRATCH_DB" "$DUMP"
RTO=$(( $(date +%s) - START ))
echo "5. Restore complete. RTO actual: ${RTO}s"

# 6. Verify integrity in the restored copy.
DST_COUNT=$(q "$SCRATCH_DB" "select count(*) from \"$TABLE\"")
DST_CKSUM=$(q "$SCRATCH_DB" "$CKSUM_SQL")
echo "6. Verify:"
[ "$DST_COUNT" = "$SRC_COUNT" ] && echo "   PASS rows match ($DST_COUNT)"               || { echo "   FAIL rows $DST_COUNT != $SRC_COUNT"; fail=1; }
[ "$DST_CKSUM" = "$SRC_CKSUM" ] && echo "   PASS content checksum matches (all columns)" || { echo "   FAIL content checksum drift"; fail=1; }

# 7. Clean up — drop the scratch DB AND remove the dump (it may hold Confidential/PII data).
psql -d postgres -q -c "drop database if exists \"$SCRATCH_DB\""
rm -f "$DUMP" 2>/dev/null || true
echo "7. Scratch DB dropped + dump removed (drill leaves no residue)."

echo "-----------------------------------"
if [ "$fail" = 0 ]; then
  echo "DR DRILL PASS — restored + integrity verified. RTO actual ${RTO}s (target <4h). RPO marker $BACKUP_TS."
  exit 0
else
  echo "DR DRILL FAIL — see FAIL lines above."
  exit 1
fi
