#!/usr/bin/env bash
# Delete MySQL database and/or user (carlo_ prefix enforced)
# Usage:
#   carlo-mysql-delete.sh db <db_name>
#   carlo-mysql-delete.sh user <user_name> [<host>]
#   carlo-mysql-delete.sh both <db_name> <user_name> [<host>]
set -euo pipefail

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
err() { echo "{\"success\":false,\"error\":$(printf '%s' "$1" | json_escape)}"; exit 1; }

[ $# -ge 2 ] || err "usage: mode and name(s) required"
MODE=$1; shift

if ! command -v mysql >/dev/null 2>&1; then err "mysql client not found"; fi

HOST=%

drop_db() {
  local DB_NAME=$1
  case "$DB_NAME" in carlo_*) ;; *) err "db_name must start with carlo_";; esac
  mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
}

drop_user() {
  local USER_NAME=$1
  local H=${2:-$HOST}
  case "$USER_NAME" in carlo_*) ;; *) err "user_name must start with carlo_";; esac
  mysql -e "DROP USER IF EXISTS '$USER_NAME'@'$H'; FLUSH PRIVILEGES;"
}

case "$MODE" in
  db)
    DB=$1
    drop_db "$DB"
    ;;
  user)
    USER=$1; H=${2:-$HOST}
    drop_user "$USER" "$H"
    ;;
  both)
    DB=$1; USER=$2; H=${3:-$HOST}
    drop_user "$USER" "$H" || true
    drop_db "$DB"
    ;;
  *) err "invalid mode: $MODE";;
esac

echo '{"success":true}'
