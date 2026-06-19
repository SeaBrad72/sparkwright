#!/bin/sh
# guard-core.sh — runtime-agnostic deny-matrix (the SINGLE SOURCE OF TRUTH).
# Pure: no stdin parsing, no runtime-specific emit. Each check prints the "13: …"
# reason to STDOUT and returns 1 (deny); returns 0 (allow) with no output.
# Consumed by: .claude/hooks/guard.sh (Claude PreToolUse), hooks/pre-push (git),
# scripts/kit-guard (CLI). See docs/operations/runtime-guards.md.
# A SPEED BUMP, not a boundary — the real control is platform-owned
# (docs/enterprise/platform-safety-boundary.md). POSIX sh; no `local` (dash-clean).

selfedit_allowed() { [ "${KIT_GUARD_SELFEDIT:-0}" = "1" ]; }

# control-plane paths an agent must never silently modify (guard integrity + gates).
is_control_plane_path() {
  case "$1" in
    *.claude/hooks/guard.sh|*.claude/hooks/guard-core.sh|\
    *.claude/settings.json|*.claude/settings.local.json|\
    *.claude/mcp-policy.json|.claude/mcp-policy.json|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    */.github/workflows/*|.github/workflows/*|*/CODEOWNERS|CODEOWNERS|*/.git/*|.git/*|\
    conformance/*|*/conformance/*|adapters/*|*/adapters/*|\
    scripts/fixtures/*|*/scripts/fixtures/*|\
    scripts/incept.sh|*/scripts/incept.sh|scripts/dora.sh|*/scripts/dora.sh|\
    scripts/agent-scorecard.sh|*/scripts/agent-scorecard.sh|\
    scripts/agent-trace.sh|*/scripts/agent-trace.sh|\
    scripts/coverage-ratchet.sh|*/scripts/coverage-ratchet.sh|\
    scripts/license-check.sh|*/scripts/license-check.sh|\
    scripts/preflight.sh|*/scripts/preflight.sh|\
    scripts/new-adapter.sh|*/scripts/new-adapter.sh|\
    scripts/new-profile.sh|*/scripts/new-profile.sh|\
    scripts/doctor.sh|*/scripts/doctor.sh|\
    scripts/postmortem.sh|*/scripts/postmortem.sh|\
    scripts/tier-advice.sh|*/scripts/tier-advice.sh|\
    scripts/sparkwright|*/scripts/sparkwright|\
    DEVELOPMENT-STANDARDS.md|*/DEVELOPMENT-STANDARDS.md|\
    DEVELOPMENT-PROCESS.md|*/DEVELOPMENT-PROCESS.md|\
    CLAUDE.md|*/CLAUDE.md)
      return 0 ;;
  esac
  return 1
}

# guard_check_read "<file>": deny reading SECRET material into the agent's context (the read half of
# exfil, A8 family 6) — the secret then reaches the model provider / logs / a PR. Symmetric with the
# secret-WRITE deny in guard_check_path but NARROWER: it does NOT deny control-plane reads (reading the
# guard/CI to understand it is legitimate). Template env files (.env.example/.sample/.template/.dist)
# are allowed; a single file_path means `*.env.*` is safe here (no multi-arg form to abuse). Honest
# ceilings: an interpreter (python -c open()) bypasses the shell path, and jq-absent leaves Read allowed.
guard_check_read() {
  fp=$1
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
  esac
  if ! selfedit_allowed; then
    case "$fp" in
      *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*)
        printf '13: reading secret material (%s) into context is the read half of exfil (-> model/logs/PR) - human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
    esac
  fi
  return 0
}

# guard_check_command "<cmd>": print reason + return 1 if denied, else return 0.
guard_check_command() {
  cmd=$1
  # --- control-plane shell mutation (moved from guard.sh:81-93, + new files) ---
  if ! selfedit_allowed && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+config[[:space:]]+([^;&|]*[[:space:]])?core\.hooksPath'; then
    printf '%s' '13: git config core.hooksPath would disable the agent guard - human-gated. Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  if ! selfedit_allowed && printf '%s' "$cmd" | grep -Eq '(\.claude(/|[[:space:]]|$)|\.github/workflows|/CODEOWNERS|(^|[^a-zA-Z.])CODEOWNERS|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard)'; then
    if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])(rm|rmdir|mv|cp|truncate|shred|chmod|chown|dd|sed|tee|ln|install|patch)[[:space:]]' \
       || printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+(checkout|restore)([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eq '>[[:space:]]*[^[:space:]]*(\.claude|\.github/workflows|CODEOWNERS|\.git|hooks/pre-push|scripts/kit-guard)'; then
      # WS1 (DENY-BY-DEFAULT): the co-occurrence test above is the safe FLOOR — it would deny. Allow
      # back ONLY a provably-safe SINGLE READ command: no ;/&&/||/|/&/redirect chaining, and a leading
      # verb (after stripping a leading backslash / env-assignments / sudo+common wrappers) that is a
      # read tool, or `sed` without -i. A read command cannot mutate the path it merely mentions. Any
      # unrecognized leading token (wrapper, interpreter, prefix) is NOT proven safe → stays denied.
      _safe=0
      if ! printf '%s' "$cmd" | grep -Eq '[;&|<>$()`]'; then
        _lead=$(printf '%s' "$cmd" | sed -E 's/^[[:space:]]*\\?//; s/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//; s/^[[:space:]]*(sudo|command|env|exec|time|nice|nohup|stdbuf|builtin)[[:space:]]+//; s/[[:space:]].*$//')
        # STRICT read-only set: every tool here writes ONLY to stdout. Deliberately EXCLUDES any tool
        # with a write/exec escape: sed (w/e cmds), awk (system()/print>), find (-exec/-delete),
        # sort -o, uniq <out>, less/more (!cmd), xxd (-r writes a file). Those stay denied (a residual:
        # use cat/grep, or KIT_GUARD_SELFEDIT). Command substitution / chaining is rejected by the
        # [;&|<>$()`] guard above, so a read leading-verb cannot front a hidden write.
        case "$_lead" in
          grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|file|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink)
            _safe=1 ;;
        esac
      fi
      if [ "$_safe" = 0 ]; then
        printf '%s' '13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
      fi
    fi
  fi
  # H3a: secret-in-context (shell) — a content-read verb (cat/grep/strings/diff/awk/...; also
  # source/. which load a .env into the environment) targeting secret material pulls it into the
  # agent's context: the read half of exfil. Human-gate it, symmetric with the secret-WRITE deny in
  # guard_check_path. ls (metadata) is excluded; template env files (.env.example/.sample/.template/
  # .dist) are NOT in the secret-suffix list so they stay allowed (no command-wide exclusion, which
  # a `cat .env.example .env` multi-arg form could abuse). Honest ceiling: an interpreter
  # (python -c open()) or an uncommon content-emitter not in the verb list bypasses — the robust
  # path is the Read-tool deny (guard_check_read) + platform containment. Asymmetry by design: the
  # shell path enumerates common .env.<suffix> files, while the Read tool's `*.env.*` glob catches
  # any suffix (e.g. `.env.foo` / `.env.local.bak` slip the shell path but the Read equivalent denies).
  if ! selfedit_allowed \
     && printf '%s' "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])[[:space:]]*(cat|less|more|head|tail|grep|egrep|fgrep|rg|strings|xxd|od|hexdump|base64|nl|tac|diff|cmp|comm|awk|sed|sort|uniq|cut|paste|fold|jq|yq|rev|source|\.)[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eq '\.env(\.(local|production|development|staging|test|prod|dev|stage|qa|preview|ci|bak|old))?([[:space:];|&*]|$)|\.(pem|key)([[:space:];|&*]|$)|id_rsa|(^|[[:space:]/;|&])secrets?/'; then
    printf '%s' '13: reading secret material into context (the read half of exfil -> model/logs/PR) is human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # --- destructive matrix: moved VERBATIM from guard.sh:96-242 ---
  # recursive rm in any flag arrangement (-rf, -fr, -r -f, --recursive), bounded so
  # 'confirm'/'npm' are not matched, but quoted forms (bash -c "rm -rf") are.
  if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])rm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alnum:]]*[rR]|--recursive)'; then
    { printf '%s' '13: recursive rm is irreversible - human-gated.'; return 1; }
  fi
  # 9b: non-recursive rm of a DANGEROUS target — a glob, a data/critical file extension,
  # an absolute path, or a dotfile of record. Anchored to command position so a commit
  # message mentioning rm is not matched. Plain relative single files (rm stale.txt,
  # rm dist/bundle.js) remain ALLOWED to avoid over-blocking normal dev work.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]'; then
    if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(--[[:space:]]+)?[^;&|[:space:]]*[*?[][^;&|[:space:]]*([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?/[^[:space:]]' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*(\.env|/\.git)([[:space:]]|$|/)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?\.env([[:space:]]|$)'; then
      { printf '%s' '13: rm of a glob, data file, absolute path, or dotfile-of-record can be irreversible - human-gated.'; return 1; }
    fi
  fi
  # 9b: non-rm destruction primitives. Binaries are anchored to COMMAND POSITION
  # (start, or after a ; && || | separator, optional sudo) so a word like "truncate"
  # inside a commit message is NOT matched — only an actually-invoked command is.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(truncate|shred|wipefs|blkdiscard|mkfs(\.[a-z0-9]+)?)([[:space:]]|$)'; then
    { printf '%s' '13: in-place file/device destruction (truncate/shred/wipefs/blkdiscard/mkfs) is irreversible - human-gated.'; return 1; }
  fi
  # dd is a scalpel like rm: deny only when of= targets a device or a data-file extension
  # (dd of=test-fixture.img stays allowed; dd of=/dev/sda and dd of=db.sqlite are denied).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?dd[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq 'of=(/dev/|[^[:space:]]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$))'; then
    { printf '%s' '13: dd of= a device or data file overwrites it irreversibly - human-gated.'; return 1; }
  fi
  # redirection/empty-source truncation of an existing target
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*):[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '/dev/null[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(cat|cp)[[:space:]]+/dev/null[[:space:]]+[>]?[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)echo[[:space:]]+-n[[:space:]]*>[[:space:]]*[^[:space:]&|;]+'; then
    { printf '%s' '13: redirection/empty-source truncation zeroes a file irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-delete([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-exec[[:space:]]+(rm|shred|truncate)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(sudo[[:space:]]+)?xargs[[:space:]]+([^|]*[[:space:]])?(rm|shred|truncate|unlink|wipefs)([[:space:]]|$)'; then
    { printf '%s' '13: bulk irreversible deletion (find -delete / -exec rm / pipe to xargs rm) - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rsync[[:space:]]+[^|]*--delete([[:space:]]|$|[^a-z])'; then
    { printf '%s' '13: rsync --delete mirrors a source and removes destination files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)git[[:space:]]+clean[[:space:]]+[^|]*-[a-z]*[fdx]'; then
    { printf '%s' '13: git clean -f/-d/-x force-deletes untracked/ignored files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?mv[[:space:]]+[^;&|]*[[:space:]]/dev/null([[:space:]]|$)'; then
    { printf '%s' '13: moving a file onto /dev/null destroys its contents - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+reset[[:space:]]+.*--hard'; then
    { printf '%s' '13: git reset --hard discards work irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(npm|yarn|pnpm)[[:space:]]+publish'; then
    { printf '%s' '13: publishing a package is externally irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*(--force|--force-with-lease|--mirror|[[:space:]]-f([[:space:]]|$)|[[:space:]+]\+[^[:space:]]*[[:space:]]*$)'; then
    { printf '%s' '13: force/mirror push rewrites or deletes published history - human-gated.'; return 1; }
  fi
  # push to main/master in any refspec form: 'main', '+main', 'HEAD:main', 'x:master', "main" (incl. git -c … push)
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*[^a-zA-Z0-9_.-](main|master)([^a-zA-Z0-9_.-]|$)'; then
    { printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1; }
  fi
  # destructive SQL via a DB client
  if printf '%s' "$cmd" | grep -Eiq '(psql|mysql|mariadb|sqlite3|mongosh?).*(drop[[:space:]]+(table|database)|truncate|delete[[:space:]]+from)'; then
    { printf '%s' '13: destructive SQL (DROP/TRUNCATE/DELETE via a DB client) - human-gated.'; return 1; }
  fi
  # destructive DB resets via migration runners
  if printf '%s' "$cmd" | grep -Eiq '(prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|]*--force-reset|sequelize[^|]*db:migrate:undo:all|knex[^|]*migrate:rollback[^|]*--all|drizzle-kit[[:space:]]+push)'; then
    { printf '%s' '13: destructive DB reset via a migration runner - human-gated.'; return 1; }
  fi
  # dropdb as an invoked command (start or after a shell separator), not when merely
  # mentioned in prose (e.g. a commit message "fix dropdb bug").
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)dropdb([[:space:]]|$)'; then
    { printf '%s' '13: dropdb destroys a database irreversibly - human-gated.'; return 1; }
  fi
  # ORM / framework DB destruction (drop/reset/wipe/fresh) across stacks
  if printf '%s' "$cmd" | grep -Eiq '(rails|rake)[[:space:]]+db:(drop|reset|migrate:reset|purge)|artisan[[:space:]]+(migrate:fresh|migrate:reset|db:wipe)|manage\.py[[:space:]]+(flush|reset_db|sqlflush)|alembic[[:space:]]+downgrade[[:space:]]+base|flyway[[:space:]]+clean|dotnet[[:space:]]+ef[[:space:]]+database[[:space:]]+(drop|update[[:space:]]+0)'; then
    { printf '%s' '13: destructive DB drop/reset via an ORM/framework tool - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'pg_restore[^|]*(--clean|[[:space:]]-c([[:space:]]|$))'; then
    { printf '%s' '13: pg_restore --clean drops objects irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq 'redis-cli[^|]*(flushall|flushdb)'; then
    { printf '%s' '13: redis FLUSHALL/FLUSHDB wipes the datastore - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'kubectl[[:space:]]+([^|]*[[:space:]])?delete([[:space:]]|$)'; then
    { printf '%s' '13: kubectl delete removes cluster resources - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+(volume[[:space:]]+(rm|prune)|system[[:space:]]+prune[^|]*(-a|--all))'; then
    { printf '%s' '13: docker volume/system prune destroys persistent state - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'aws[[:space:]]+s3[[:space:]]+rm[^|]*--recursive|aws[[:space:]]+s3[[:space:]]+rb|aws[[:space:]]+rds[[:space:]]+delete-db-instance|aws[[:space:]]+dynamodb[[:space:]]+delete-table|gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+delete|az[[:space:]]+group[[:space:]]+delete|az[[:space:]]+sql[^|]*[[:space:]]delete'; then
    { printf '%s' '13: cloud resource deletion (storage/DB/instance) is irreversible - human-gated.'; return 1; }
  fi
  # 9b: cloud/infra destruction as capability families (verb-agnostic across vendors)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)terraform[[:space:]]+(destroy|apply)([[:space:]]|$)'; then
    { printf '%s' '13: terraform destroy/apply changes real infrastructure - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(aws|gcloud|az)[[:space:]][^|]*[[:space:]](delete|delete-[a-z-]+|terminate-[a-z-]+|remove|rb|destroy)([[:space:]]|$)'; then
    { printf '%s' '13: cloud resource deletion/termination is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)helm[[:space:]]+(uninstall|delete)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)kubectl[[:space:]]+(drain|cordon)([[:space:]]|$)'; then
    { printf '%s' '13: helm uninstall / kubectl drain disrupts running workloads - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(mongosh?|cockroach|psql|mysql)[^|]*(dropDatabase|drop[[:space:]]+database)' \
     || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(liquibase[[:space:]]+dropAll|flyway[[:space:]]+undo)'; then
    { printf '%s' '13: database drop via a client/migration tool is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(curl|wget|base64[[:space:]]+(-d|--decode)|xxd[[:space:]]+-r)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash|python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'; then
    { printf '%s' '13: piping a fetched/decoded payload into a shell is high-blast-radius - human-gated.'; return 1; }
  fi
  # 9b: data-exfiltration channels (PARTIAL — binary-name denial only; interpreters
  # (python -c, node -e) remain channels. The real control is the platform network-egress
  # allowlist — see docs/enterprise/platform-safety-boundary.md. This is a speed bump.)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(scp|sftp)[[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(curl|wget)[[:space:]][^|]*(-T[[:space:]]|--upload-file|-F[[:space:]]*[^[:space:]&|;]*@|--data-binary[[:space:]]*@|--post-file)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(nc|ncat|netcat)[[:space:]]+[^[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)rclone[[:space:]]+(copy|sync|move)[[:space:]][^|]*[a-zA-Z0-9_-]+:' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*mail[[:space:]]'; then
    { printf '%s' '13: possible data exfiltration (scp/sftp/curl-upload/nc/rclone/mail). Partial guard - the boundary is the platform egress allowlist - human-gated.'; return 1; }
  fi
  # 9b: eval of a command substitution hides the real command from inspection.
  # Anchored to command position so "eval $(...)" inside a commit message is NOT matched.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?eval[[:space:]]+[^;&|]*(\$\(|`)'; then
    { printf '%s' '13: eval of a command substitution obscures the executed command - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(vercel[[:space:]]+(deploy[[:space:]]+)?--prod|railway[[:space:]]+up|fly[[:space:]]+deploy|terraform[[:space:]]+apply|kubectl[[:space:]]+apply|helm[[:space:]]+(install|upgrade))'; then
    { printf '%s' '13: production deploy / infra apply is high-blast-radius - human-gated.'; return 1; }
  fi
  # prod-context catch-all: a mutating kube/helm op against a production context or namespace.
  # Patterns are intentionally `.`-prefixed (not leading `--`) so GNU grep does not parse them
  # as options; the leading `.` matches the space that always precedes the flag in real commands.
  if printf '%s' "$cmd" | grep -Eiq '.(-(kube-)?context[[:space:]=][^[:space:]]*prod)|[[:space:]]-n[[:space:]]+[^[:space:]]*prod' \
     && printf '%s' "$cmd" | grep -Eiq '(kubectl|helm)[[:space:]]([^|]*[[:space:]])?(apply|delete|create|replace|patch|scale|rollout|upgrade|install|uninstall|destroy)'; then
    { printf '%s' '13: mutating operation against a production context - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)([A-Z_]*ENV)=prod[a-z]*[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command in a production environment - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '.(--(env|environment)[[:space:]=]prod)' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command targeting production - human-gated.'; return 1; }
  fi
  return 0
}

# guard_check_mcp "<tool>" "<allowlist>" "<overrides>": ALLOW (return 0) / DENY (return 1 + reason).
# Pure: the adapter loads the policy and passes it in (the core never reads a file).
#   <tool>      a Claude MCP tool name, mcp__<server>__<action> (action = segment after the last __)
#   <allowlist> newline list of exact mcp__server__action OR mcp__server__* wildcards (explicit permit)
#   <overrides> newline list of "mcp__server__action=class" (reclassify; class 'read'/'data.read' => allow)
# Decision: allowlist > override-class > tokenized action-verb heuristic > fail-closed deny.
#   The heuristic tokenizes the action (camelCase->snake, lowercased): the first token must be a
#   read verb to allow, and ANY destructive verb token downgrades to deny (so get_and_delete /
#   fetchAndExport deny; list_deployments / get_updates stay read - the noun is not the verb).
# secret.read (A8 family 6) is deny-by-default by NAME: an action naming secret material, or a
# known secret-store server on a read, is denied even when a read verb leads.
# Honest ceiling: classifies by what the NAME reveals; a renamed action (get_data that exfiltrates),
# a secret read via a generic-named server/action (mcp__storage__read_blob), a server wildcard that
# admits a destructive tool, and real egress are NOT caught here — the platform egress allowlist +
# the 11c sandbox are the real controls (docs/enterprise/platform-safety-boundary.md).
guard_check_mcp() {
  t=$1; al=$2; ov=$3
  # 1. explicit allowlist: exact tool, or its server wildcard (mcp__server__*)
  if printf '%s\n' "$al" | grep -qxF -- "$t" 2>/dev/null; then return 0; fi
  if printf '%s\n' "$al" | grep -qxF -- "${t%__*}__*" 2>/dev/null; then return 0; fi
  # 2. class: a per-tool override wins; else heuristic on the action segment.
  act=${t##*__}
  _rest=${t#mcp__}; srv=$(printf '%s' "${_rest%%__*}" | tr 'A-Z' 'a-z')  # server segment, lowercased
  cls=$(printf '%s\n' "$ov" | while IFS='=' read -r k v; do [ "$k" = "$t" ] && { printf '%s' "$v"; break; }; done || true)
  if [ -z "$cls" ]; then
    # Tokenize the action: split camelCase to snake, lowercase, turn _/- into spaces.
    # Whole-token verb matching keeps legit compounds read (list_deployments, get_updates -
    # 'deployments'/'updates' are not the verbs 'deploy'/'update') while downgrading a read-
    # prefixed action that carries a destructive verb token (get_and_delete, fetchAndExport).
    rverbs=' read get list search query fetch describe show view find count '
    dverbs=' delete drop destroy remove truncate reset write update create insert upsert patch put set upload publish deploy send post email notify apply merge push revoke rotate export download '
    norm=$(printf '%s' "$act" | sed 's/\([a-zA-Z0-9]\)\([A-Z]\)/\1_\2/g' | tr 'A-Z_-' 'a-z  ')
    first=${norm%% *}
    cls=unknown
    case "$rverbs" in *" $first "*) cls=read ;; esac
    for tok in $norm; do
      case "$dverbs" in *" $tok "*) cls=destructive; break ;; esac
    done
    # secret-material READ is deny-by-default even when a read verb leads (A8 family 6 - the read
    # half of exfil). Catch it by NAME: (a) the action names secret material, or (b) the server is
    # a known secret store on a read. Ceiling: a secret read via a generic-named server/action
    # (e.g. mcp__storage__read_blob holding a secret) is NOT caught - that is the 11c sandbox's job.
    if [ "$cls" = "read" ] && printf '%s' "$act" | grep -Eiq 'secret|credential|passphrase|password|api[_-]?key|private[_-]?key|access[_-]?key|secret[_-]?key|auth[_-]?token|access[_-]?token'; then
      cls=secret.read
    fi
    if [ "$cls" = "read" ] && printf '%s' "$srv" | grep -Eiq 'vault|1password|onepassword|secretsmanager|secrets[_-]?manager|secret[_-]?manager|keyvault|key[_-]?vault|credstash|doppler|infisical|akeyless'; then
      cls=secret.read
    fi
  fi
  case "$cls" in
    read|data.read) return 0 ;;
    secret.read) printf '13: MCP tool %s reads secret/credential material - deny-by-default (the read half of exfil; A8 family 6). Allowlist it in .claude/mcp-policy.json if intended.' "$t"; return 1 ;;
    unknown) printf '13: MCP tool %s is not classifiable as read-only - denied (fail-closed). Allowlist it in .claude/mcp-policy.json if safe.' "$t"; return 1 ;;
    *) printf '13: MCP tool %s is a destructive/egress capability (%s) - human-gated. Allowlist it in .claude/mcp-policy.json if intended.' "$t" "$cls"; return 1 ;;
  esac
}

# guard_check_path "<path>": print reason + return 1 if denied, else 0.
# Moved from guard.sh:245-265 (drop the jq line — caller passes the path).
guard_check_path() {
  fp=$1
  fpn=$(printf '%s' "$fp" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e 's#^\./##' -e 's#/*$##' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta')
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  if ! selfedit_allowed && { is_control_plane_path "$fp" || is_control_plane_path "$fpn"; }; then
    printf '%s' '13: modifying the guard / its config / CI gates is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # WS1: validate by basename when the NORMALIZED path has no real parent directory — either it is a
  # bare name, OR it still ESCAPES its root (a leading/unresolved `..` the fixpoint could not consume),
  # which cannot be trusted by directory. A path with a genuine parent dir (`.vscode/settings.json`) is
  # matched precisely by is_control_plane_path above, so the net is skipped only there. This closes the
  # `./settings.json`, `a/../guard.sh`, multi-`..`, trailing-slash, AND leading-`../name` bypasses while
  # still allowing an innocent `.vscode/settings.json` / `app/config/settings.json`.
  if ! selfedit_allowed; then
    _bare=1
    case "$fpn" in
      ..|../*|*/../*) _bare=1 ;;
      */*)           _bare=0 ;;
    esac
    if [ "$_bare" = 1 ]; then
      case "$base" in
        guard.sh|guard-core.sh|kit-guard|pre-push|settings.json|settings.local.json|mcp-policy.json|CODEOWNERS)
          printf '13: modifying a control-plane file (%s) is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
      esac
    fi
  fi
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
  esac
  case "$fp" in
    *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*)
      printf '13: writing secret material (%s) - human-gated (use .env.example + a secrets manager).' "$base"; return 1 ;;
  esac
  return 0
}

# guard_check_push <remote-ref> <local-sha> <remote-sha>: print reason + return 1 if denied.
# Ref-based (more precise than the command-string git rules): real non-fast-forward detection.
guard_check_push() {
  remote_ref=$1; local_sha=$2; remote_sha=$3
  zero=0000000000000000000000000000000000000000
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      if [ "$local_sha" = "$zero" ]; then
        printf '%s' '13: deleting main/master is destructive and bypasses review - human-gated.'; return 1
      fi
      printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1 ;;
  esac
  # force-push / non-fast-forward to ANY branch: remote tip not an ancestor of the new tip.
  if [ "$remote_sha" != "$zero" ] && [ "$local_sha" != "$zero" ]; then
    if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
      printf '%s' '13: non-fast-forward (force) push rewrites published history - human-gated.'; return 1
    fi
  fi
  return 0
}
