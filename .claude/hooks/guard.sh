#!/bin/sh
# guard.sh — PreToolUse hook enforcing the §13 autonomy matrix (DEVELOPMENT-PROCESS.md).
# Denies irreversible / high-blast-radius actions; defers everything else to normal
# permission handling. Reads the tool-call JSON on stdin and, when a denied pattern
# matches the relevant input FIELD ONLY (Bash .command / Write|Edit .file_path) — not
# the whole payload — prints a deny decision and exits 0. Field-scoping means editing a
# doc that merely *mentions* a dangerous command (in file CONTENT) is NOT blocked.
#
# Within the Bash .command field, matching errs toward OVER-blocking: a dangerous token
# inside a quoted string (e.g. bash -c with a recursive-rm payload, or an echo of the
# same) is denied, because a guard cannot safely distinguish quoting from execution and
# under-blocking a real deletion is worse than over-blocking an echo.
#
# Covered: recursive rm, force-push, push to main/master, destructive SQL/DDL,
# migration-runner resets, ORM/cloud/cluster DB destruction, and a
# production-context catch-all.
#
# Requires `jq`. If jq is absent, OR the tool input is not valid JSON, mutating tools
# (Bash/Write/Edit/NotebookEdit) are denied (fail-safe toward caution); read-only allowed.
set -eu

INPUT=$(cat)

emit_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}
allow() { exit 0; }   # no output = defer to normal permission flow

# best-effort tool name without jq (only used to decide the fail-safe deny)
tool_name_grep() {
  printf '%s' "$INPUT" | tr -d '\n' | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}
deny_if_mutating() {
  case "$1" in
    Bash|Write|Edit|NotebookEdit)
      emit_deny "agent-guard: $2 (DEVELOPMENT-PROCESS.md 13). Mutating tools are denied until resolved." ;;
    *) allow ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  deny_if_mutating "$(tool_name_grep)" "jq is required to evaluate tool safety; install jq"
fi

# Parse the tool name. If the payload is not valid JSON, jq exits non-zero — FAIL CLOSED
# (deny mutating tools) instead of letting set -e kill the script with no decision (which
# a PreToolUse hook treats as "proceed").
if ! TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null); then
  # Unparseable input: we can verify nothing, so deny outright (fail closed). Claude Code
  # always sends valid JSON to hooks, so this path is an anomaly, not normal operation.
  emit_deny "agent-guard: tool input is not valid JSON — cannot verify safety; denying (DEVELOPMENT-PROCESS.md 13)."
fi

case "$TOOL" in
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || printf '')
    # recursive rm in any flag arrangement (-rf, -fr, -r -f, --recursive), bounded so
    # 'confirm'/'npm' are not matched, but quoted forms (bash -c "rm -rf") are.
    if printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_])rm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alnum:]]*[rR]|--recursive)'; then
      emit_deny "13: recursive rm is irreversible - human-gated."
    fi
    # 9b: non-recursive rm of a DANGEROUS target — a glob, a data/critical file extension,
    # an absolute path, or a dotfile of record. Anchored to command position so a commit
    # message mentioning rm is not matched. Plain relative single files (rm stale.txt,
    # rm dist/bundle.js) remain ALLOWED to avoid over-blocking normal dev work.
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]'; then
      if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(--[[:space:]]+)?[^;&|[:space:]]*[*?[][^;&|[:space:]]*([[:space:]]|$)' \
         || printf '%s' "$CMD" | grep -Eiq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$)' \
         || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?/[^[:space:]]' \
         || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*(\.env|/\.git)([[:space:]]|$|/)' \
         || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?\.env([[:space:]]|$)'; then
        emit_deny "13: rm of a glob, data file, absolute path, or dotfile-of-record can be irreversible - human-gated."
      fi
    fi
    # 9b: non-rm destruction primitives. Binaries are anchored to COMMAND POSITION
    # (start, or after a ; && || | separator, optional sudo) so a word like "truncate"
    # inside a commit message is NOT matched — only an actually-invoked command is.
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?(truncate|shred|wipefs|blkdiscard|mkfs(\.[a-z0-9]+)?)([[:space:]]|$)'; then
      emit_deny "13: in-place file/device destruction (truncate/shred/wipefs/blkdiscard/mkfs) is irreversible - human-gated."
    fi
    # dd is a scalpel like rm: deny only when of= targets a device or a data-file extension
    # (dd of=test-fixture.img stays allowed; dd of=/dev/sda and dd of=db.sqlite are denied).
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?dd[[:space:]]' \
       && printf '%s' "$CMD" | grep -Eiq 'of=(/dev/|[^[:space:]]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$))'; then
      emit_deny "13: dd of= a device or data file overwrites it irreversibly - human-gated."
    fi
    # redirection/empty-source truncation of an existing target
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*):[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
       || printf '%s' "$CMD" | grep -Eq '/dev/null[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
       || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(cat|cp)[[:space:]]+/dev/null[[:space:]]+[>]?[[:space:]]*[^[:space:]&|;]+' \
       || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)echo[[:space:]]+-n[[:space:]]*>[[:space:]]*[^[:space:]&|;]+'; then
      emit_deny "13: redirection/empty-source truncation zeroes a file irreversibly - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-delete([[:space:]]|$)' \
       || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-exec[[:space:]]+(rm|shred|truncate)([[:space:]]|$)'; then
      emit_deny "13: find -delete / -exec rm performs bulk irreversible deletion - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?rsync[[:space:]]+[^|]*--delete([[:space:]]|$|[^a-z])'; then
      emit_deny "13: rsync --delete mirrors a source and removes destination files irreversibly - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)git[[:space:]]+clean[[:space:]]+[^|]*-[a-z]*[fdx]'; then
      emit_deny "13: git clean -f/-d/-x force-deletes untracked/ignored files irreversibly - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?mv[[:space:]]+[^;&|]*[[:space:]]/dev/null([[:space:]]|$)'; then
      emit_deny "13: moving a file onto /dev/null destroys its contents - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+reset[[:space:]]+.*--hard'; then
      emit_deny "13: git reset --hard discards work irreversibly - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+commit[[:space:]]+.*--amend'; then
      emit_deny "13: git commit --amend rewrites history - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(npm|yarn|pnpm)[[:space:]]+publish'; then
      emit_deny "13: publishing a package is externally irreversible - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$)|[[:space:]+]\+[^[:space:]]*[[:space:]]*$)'; then
      emit_deny "13: force-push rewrites published history - human-gated."
    fi
    # push to main/master in any refspec form: 'main', '+main', 'HEAD:main', 'x:master' (incl. git -c … push)
    if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*[[:space:]:+/](main|master)([[:space:]]|:|$)'; then
      emit_deny "13: pushing directly to main/master bypasses review - open a PR (human-gated)."
    fi
    # destructive SQL via a DB client
    if printf '%s' "$CMD" | grep -Eiq '(psql|mysql|mariadb|sqlite3|mongosh?).*(drop[[:space:]]+(table|database)|truncate|delete[[:space:]]+from)'; then
      emit_deny "13: destructive SQL (DROP/TRUNCATE/DELETE via a DB client) - human-gated."
    fi
    # destructive DB resets via migration runners
    if printf '%s' "$CMD" | grep -Eiq '(prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|]*--force-reset|sequelize[^|]*db:migrate:undo:all|knex[^|]*migrate:rollback[^|]*--all|drizzle-kit[[:space:]]+push)'; then
      emit_deny "13: destructive DB reset via a migration runner - human-gated."
    fi
    # dropdb as an invoked command (start or after a shell separator), not when merely
    # mentioned in prose (e.g. a commit message "fix dropdb bug").
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)dropdb([[:space:]]|$)'; then
      emit_deny "13: dropdb destroys a database irreversibly - human-gated."
    fi
    # ORM / framework DB destruction (drop/reset/wipe/fresh) across stacks
    if printf '%s' "$CMD" | grep -Eiq '(rails|rake)[[:space:]]+db:(drop|reset|migrate:reset|purge)|artisan[[:space:]]+(migrate:fresh|migrate:reset|db:wipe)|manage\.py[[:space:]]+(flush|reset_db|sqlflush)|alembic[[:space:]]+downgrade[[:space:]]+base|flyway[[:space:]]+clean|dotnet[[:space:]]+ef[[:space:]]+database[[:space:]]+(drop|update[[:space:]]+0)'; then
      emit_deny "13: destructive DB drop/reset via an ORM/framework tool - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'pg_restore[^|]*(--clean|[[:space:]]-c([[:space:]]|$))'; then
      emit_deny "13: pg_restore --clean drops objects irreversibly - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eiq 'redis-cli[^|]*(flushall|flushdb)'; then
      emit_deny "13: redis FLUSHALL/FLUSHDB wipes the datastore - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'kubectl[[:space:]]+([^|]*[[:space:]])?delete([[:space:]]|$)'; then
      emit_deny "13: kubectl delete removes cluster resources - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'docker[[:space:]]+(volume[[:space:]]+(rm|prune)|system[[:space:]]+prune[^|]*(-a|--all))'; then
      emit_deny "13: docker volume/system prune destroys persistent state - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq 'aws[[:space:]]+s3[[:space:]]+rm[^|]*--recursive|aws[[:space:]]+s3[[:space:]]+rb|aws[[:space:]]+rds[[:space:]]+delete-db-instance|aws[[:space:]]+dynamodb[[:space:]]+delete-table|gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+delete|az[[:space:]]+group[[:space:]]+delete|az[[:space:]]+sql[^|]*[[:space:]]delete'; then
      emit_deny "13: cloud resource deletion (storage/DB/instance) is irreversible - human-gated."
    fi
    # 9b: cloud/infra destruction as capability families (verb-agnostic across vendors)
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)terraform[[:space:]]+(destroy|apply)([[:space:]]|$)'; then
      emit_deny "13: terraform destroy/apply changes real infrastructure - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eiq '(^|[;&|][[:space:]]*)(aws|gcloud|az)[[:space:]][^|]*[[:space:]](delete|delete-[a-z-]+|terminate-[a-z-]+|remove|rb|destroy)([[:space:]]|$)'; then
      emit_deny "13: cloud resource deletion/termination is irreversible - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)helm[[:space:]]+(uninstall|delete)([[:space:]]|$)' \
       || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)kubectl[[:space:]]+(drain|cordon)([[:space:]]|$)'; then
      emit_deny "13: helm uninstall / kubectl drain disrupts running workloads - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eiq '(mongosh?|cockroach|psql|mysql)[^|]*(dropDatabase|drop[[:space:]]+database)' \
       || printf '%s' "$CMD" | grep -Eiq '(^|[;&|][[:space:]]*)(liquibase[[:space:]]+dropAll|flyway[[:space:]]+undo)'; then
      emit_deny "13: database drop via a client/migration tool is irreversible - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(curl|wget|base64[[:space:]]+(-d|--decode)|xxd[[:space:]]+-r)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash)([[:space:]]|$)'; then
      emit_deny "13: piping a fetched/decoded payload into a shell is high-blast-radius - human-gated."
    fi
    # 9b: data-exfiltration channels (PARTIAL — binary-name denial only; interpreters
    # (python -c, node -e) remain channels. The real control is the platform network-egress
    # allowlist — see docs/enterprise/platform-safety-boundary.md. This is a speed bump.)
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?(scp|sftp)[[:space:]]' \
       || printf '%s' "$CMD" | grep -Eq '(curl|wget)[[:space:]][^|]*(-T[[:space:]]|--upload-file|-F[[:space:]]|--data-binary[[:space:]]*@|--post-file)' \
       || printf '%s' "$CMD" | grep -Eq '\|[[:space:]]*(nc|ncat|netcat)[[:space:]]+[^[:space:]]' \
       || printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)rclone[[:space:]]+(copy|sync|move)[[:space:]][^|]*[a-zA-Z0-9_-]+:' \
       || printf '%s' "$CMD" | grep -Eq '\|[[:space:]]*mail[[:space:]]'; then
      emit_deny "13: possible data exfiltration (scp/sftp/curl-upload/nc/rclone/mail). Partial guard - the boundary is the platform egress allowlist - human-gated."
    fi
    # 9b: eval of a command substitution hides the real command from inspection.
    # Anchored to command position so "eval $(...)" inside a commit message is NOT matched.
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)(sudo[[:space:]]+)?eval[[:space:]]+[^;&|]*(\$\(|`)'; then
      emit_deny "13: eval of a command substitution obscures the executed command - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eiq '(vercel[[:space:]]+(deploy[[:space:]]+)?--prod|railway[[:space:]]+up|fly[[:space:]]+deploy|terraform[[:space:]]+apply|kubectl[[:space:]]+apply|helm[[:space:]]+(install|upgrade))'; then
      emit_deny "13: production deploy / infra apply is high-blast-radius - human-gated."
    fi
    # prod-context catch-all: a mutating kube/helm op against a production context or namespace.
    # Patterns are intentionally `.`-prefixed (not leading `--`) so GNU grep does not parse them
    # as options; the leading `.` matches the space that always precedes the flag in real commands.
    if printf '%s' "$CMD" | grep -Eiq '.(-(kube-)?context[[:space:]=][^[:space:]]*prod)|[[:space:]]-n[[:space:]]+[^[:space:]]*prod' \
       && printf '%s' "$CMD" | grep -Eiq '(kubectl|helm)[[:space:]]([^|]*[[:space:]])?(apply|delete|create|replace|patch|scale|rollout|upgrade|install|uninstall|destroy)'; then
      emit_deny "13: mutating operation against a production context - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|][[:space:]]*)([A-Z_]*ENV)=prod[a-z]*[[:space:]]' \
       && printf '%s' "$CMD" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
      emit_deny "13: destructive/deploy command in a production environment - human-gated."
    fi
    if printf '%s' "$CMD" | grep -Eiq '.(--(env|environment)[[:space:]=]prod)' \
       && printf '%s' "$CMD" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
      emit_deny "13: destructive/deploy command targeting production - human-gated."
    fi
    allow ;;
  Write|Edit|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || printf '')
    BASE=$(basename "$FP" 2>/dev/null || printf '%s' "$FP")
    if [ "$BASE" = ".env.example" ]; then allow; fi
    case "$FP" in
      *.env|*/.env|*.env.local|*.env.production|*.env.development|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*)
        emit_deny "13: writing secret material ($BASE) - human-gated (use .env.example + a secrets manager)." ;;
    esac
    allow ;;
  *)
    allow ;;
esac
