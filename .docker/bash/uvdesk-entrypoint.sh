#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/var/www/uvdesk"
VAR_DIR="$APP_ROOT/var"                    # Volume is mounted here (Railway → /var/www/uvdesk/var)
UPLOAD_DIR="$APP_ROOT/public/uploads"      # Public uploads path
PERSIST_UPLOADS="$VAR_DIR/uploads"         # Uploads live inside var to persist

# --- Runtime Apache port + ServerName ---
PORT_VALUE="${PORT:-8080}"
echo "Listen ${PORT_VALUE}" > /etc/apache2/ports.conf
sed -i "s#<VirtualHost \*:[0-9]\+>#<VirtualHost *:${PORT_VALUE}>#g" /etc/apache2/sites-available/000-default.conf
echo "ServerName ${APP_URL:-localhost}" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null 2>&1 || true
# ----------------------------------------

# Ensure .env exists (env vars override it)
if [ ! -f "$APP_ROOT/.env" ] && [ -f "$APP_ROOT/.env.example" ]; then
  cp "$APP_ROOT/.env.example" "$APP_ROOT/.env" || true
fi

# Ensure var subdirs exist on the mounted volume
mkdir -p "$VAR_DIR/cache" "$VAR_DIR/log" "$PERSIST_UPLOADS"

# Symlink public/uploads -> var/uploads (persisted)
if [ ! -L "$UPLOAD_DIR" ]; then
  if [ -d "$UPLOAD_DIR" ]; then
    # move existing files once
    find "$UPLOAD_DIR" -mindepth 1 -maxdepth 1 -exec mv -t "$PERSIST_UPLOADS" {} +
    rm -rf "$UPLOAD_DIR"
  fi
  ln -s "$PERSIST_UPLOADS" "$UPLOAD_DIR"
fi

# Permissions
chown -R www-data:www-data "$APP_ROOT"
chmod -R 775 "$VAR_DIR" "$(dirname "$UPLOAD_DIR")" || true

# Always build prod cache (avoid dev container artifacts)
APP_ENV=prod APP_DEBUG=0 php "$APP_ROOT/bin/console" cache:clear --env=prod --no-debug || true

# Hand off to Apache in foreground
exec "$@"
