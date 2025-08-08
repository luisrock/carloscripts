#!/usr/bin/env bash
# Read-only: list MySQL databases and users with prefix filter
# Outputs JSON with databases[], users[] and grants[] (limited)
set -euo pipefail

PREFIX="${1:-carlo_}"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

# Ensure mysql is available
if ! command -v mysql >/dev/null 2>&1; then
  echo '{"error":"mysql client not found"}'
  exit 1
fi

# Queries
SQL_DBS="SHOW DATABASES LIKE '${PREFIX}%';"
SQL_USERS="SELECT user, host FROM mysql.user WHERE user LIKE '${PREFIX}%';"
# Grants per user will be fetched iteratively

# Collect databases
declare -a DBS=()
mapfile -t DBS < <(mysql -N -e "$SQL_DBS" || true)
# Collect users
declare -a USERS=()
while IFS=$'\t' read -r USER HOST; do
  [ -z "${USER:-}" ] && continue
  USERS+=("$USER	$HOST")
done < <(mysql -N -e "$SQL_USERS" || true)

# Build JSON arrays
DBS_JSON="[]"
if [ ${#DBS[@]} -gt 0 ]; then
  TMP=$(mktemp)
  {
    echo '['
    first=1
    for db in "${DBS[@]}"; do
      [ $first -eq 0 ] && echo ','
      first=0
      printf '  %s' "$(printf '%s' "$db" | json_escape)"
    done
    echo
    echo ']'
  } > "$TMP"
  DBS_JSON=$(cat "$TMP"); rm -f "$TMP"
fi

USERS_JSON="[]"
if [ ${#USERS[@]} -gt 0 ]; then
  TMPU=$(mktemp)
  {
    echo '['
    first=1
    for row in "${USERS[@]}"; do
      u="${row%%$'\t'*}"; h="${row##*$'\t'}";
      [ $first -eq 0 ] && echo ','
      first=0
      printf '  {"user":%s,"host":%s}' \
        "$(printf '%s' "$u" | json_escape)" \
        "$(printf '%s' "$h" | json_escape)"
    done
    echo
    echo ']'
  } > "$TMPU"
  USERS_JSON=$(cat "$TMPU"); rm -f "$TMPU"
fi

# Grants: best-effort, may be limited by privileges
GRANTS_JSON="[]"
if [ ${#USERS[@]} -gt 0 ]; then
  TMP=$(mktemp)
  {
    echo '['
    first=1
    for row in "${USERS[@]}"; do
      u="${row%%$'\t'*}"; h="${row##*$'\t'}";
      # SHOW GRANTS FOR requires quoting user@host
      GR=$(mysql -N -e "SHOW GRANTS FOR '${u}'@'${h}';" 2>/dev/null || true)
      # Join multiline into ; separated
      GR_ONE_LINE=$(printf '%s' "$GR" | tr '\n' '; ')
      [ $first -eq 0 ] && echo ','
      first=0
      printf '  {"user":%s,"host":%s,"grants":%s}' \
        "$(printf '%s' "$u" | json_escape)" \
        "$(printf '%s' "$h" | json_escape)" \
        "$(printf '%s' "$GR_ONE_LINE" | json_escape)"
    done
    echo
    echo ']'
  } > "$TMP"
  GRANTS_JSON=$(cat "$TMP"); rm -f "$TMP"
fi

# Output final JSON
cat <<JSON
{
  "prefix": $(printf '%s' "$PREFIX" | json_escape),
  "databases": $DBS_JSON,
  "users": $USERS_JSON,
  "grants": $GRANTS_JSON
}
JSON
