#!/usr/bin/env bash
# Create MySQL database and optionally user with privileges
# Usage:
#   carlo-mysql-create.sh <db_name> [<user_name>] [<password>] [<privileges_csv>] [<host>]
# Notes:
#   - db_name and user_name must start with 'carlo_'
#   - privileges_csv like: SELECT,INSERT,UPDATE,DELETE,CREATE,ALTER,DROP,INDEX
#   - host defaults to '%'
set -euo pipefail

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
err() { echo "{\"success\":false,\"error\":$(printf '%s' "$1" | json_escape)}"; exit 1; }

DB_NAME=${1:-}
USER_NAME=${2:-}
PASSWORD=${3:-}
PRIVS_CSV=${4:-}
HOST=${5:-%}

[ -z "$DB_NAME" ] && err "db_name required"
case "$DB_NAME" in carlo_*) ;; *) err "db_name must start with carlo_";; esac
if [ -n "$USER_NAME" ]; then
  case "$USER_NAME" in carlo_*) ;; *) err "user_name must start with carlo_";; esac
fi

if ! command -v mysql >/dev/null 2>&1; then err "mysql client not found"; fi

# Create database
mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"

USER_CREATED=false
GRANTED=false
if [ -n "$USER_NAME" ]; then
  if [ -z "$PASSWORD" ]; then err "password required when user_name is provided"; fi
  # Escape single quotes in password for SQL ('' inside single-quoted literal)
  PW_ESC=$(printf "%s" "$PASSWORD" | sed "s/'/''/g")
  mysql -e "CREATE USER IF NOT EXISTS '$USER_NAME'@'$HOST' IDENTIFIED BY '$PW_ESC';"
  USER_CREATED=true
  if [ -n "$PRIVS_CSV" ]; then
    # Sanitize CSV (letters, commas, underscore only)
    PRIVS=$(printf '%s' "$PRIVS_CSV" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z_,]//g')
  else
    PRIVS="SELECT,INSERT,UPDATE,DELETE"
  fi
  mysql -e "GRANT $PRIVS ON \`$DB_NAME\`.* TO '$USER_NAME'@'$HOST'; FLUSH PRIVILEGES;"
  GRANTED=true
fi

# Output JSON
cat <<JSON
{
  "success": true,
  "database": $(printf '%s' "$DB_NAME" | json_escape),
  "user": $(printf '%s' "${USER_NAME}" | json_escape),
  "host": $(printf '%s' "$HOST" | json_escape),
  "user_created": $([ "$USER_CREATED" = true ] && echo true || echo false),
  "granted": $([ "$GRANTED" = true ] && echo true || echo false)
}
JSON
