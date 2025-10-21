#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/var/www/uvdesk"
PERSIST_ROOT="/data"                  # Mount ONE Railway Volume here
UPLOAD_DIR="$APP_ROOT/public/uploads" # Adjust if your uploads live elsewhere

# --- Runtime Apache port + ServerName (no build-time templating) ---
PORT_VALUE="${PORT:-8080}"
echo "Listen ${PORT_VALUE}" > /etc/apache2/ports.conf
sed -i "s#<VirtualHost \*:[0-9]\+>#<VirtualHost *:${PORT_VALUE}>#g" /etc/apache2/sites-available/000-default.conf
echo "ServerName ${APP_URL:-localhost}" > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null 2>&1 || true
# -------------------------------------------------------------------

# Ensure .env exists (first boot)
if [ ! -f "$APP_ROOT/.env" ] && [ -f "$APP_ROOT/.env.example" ]; then
  cp "$APP_ROOT/.env.example" "$APP_ROOT/.env" || true
fi

# --- Single-volume persistence wiring (var/ + uploads) ---
mkdir -p "$PERSIST_ROOT/var" "$PERSIST_ROOT/uploads"

copy_dir() {
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$1/" "$2/" || true
  else
    cp -a "$1/." "$2/" || true
  fi
}

# var/ (cache, logs, runtime)
if [ ! -L "$APP_ROOT/var" ]; then
  if [ -d "$APP_ROOT/var" ] && [ -n "$(ls -A "$APP_ROOT/var" 2>/dev/null)" ]; then
    copy_dir "$APP_ROOT/var" "$PERSIST_ROOT/var"
  fi
  rm -rf "$APP_ROOT/var"
  ln -s "$PERSIST_ROOT/var" "$APP_ROOT/var"
fi

# uploads
if [ ! -L "$UPLOAD_DIR" ]; then
  mkdir -p "$(dirname "$UPLOAD_DIR")"
  if [ -d "$UPLOAD_DIR" ] && [ -n "$(ls -A "$UPLOAD_DIR" 2>/dev/null)" ]; then
    copy_dir "$UPLOAD_DIR" "$PERSIST_ROOT/uploads"
  fi
  rm -rf "$UPLOAD_DIR"
  ln -s "$PERSIST_ROOT/uploads" "$UPLOAD_DIR"
fi

# Permissions for Apache/PHP
chown -R www-data:www-data "$PERSIST_ROOT" "$APP_ROOT" || true
chmod -R 775 "$PERSIST_ROOT" "$APP_ROOT/var" "$(dirname "$UPLOAD_DIR")" || true

# Clear+warm cache (non-fatal on first boot)
php "$APP_ROOT/bin/console" cache:clear --env=prod --no-debug || true

# IMPORTANT: Do NOT run doctrine:migrations:migrate here – UVdesk skeleton doesn't ship them.
# Optional hands-off schema creation (uncomment if desired):
# if [ -n "${DATABASE_URL:-}" ]; then
#   php "$APP_ROOT/bin/console" doctrine:schema:update --force --complete || true
# fi

# Hand off to CMD (apachectl -D FOREGROUND)
exec "$@"
