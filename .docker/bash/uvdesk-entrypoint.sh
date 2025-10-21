#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/var/www/uvdesk"
PERSIST_ROOT="/data"                 # Mount a single Railway Volume here
UPLOAD_DIR="$APP_ROOT/public/uploads" # Adjust if your uploads live elsewhere

# Ensure .env exists (first boot)
if [ ! -f "$APP_ROOT/.env" ] && [ -f "$APP_ROOT/.env.example" ]; then
  cp "$APP_ROOT/.env.example" "$APP_ROOT/.env" || true
fi

# --- Single-volume persistence wiring (Railway gives one volume per service)
mkdir -p "$PERSIST_ROOT/var" "$PERSIST_ROOT/uploads"

# var/ (cache, logs, runtime)
if [ ! -L "$APP_ROOT/var" ]; then
  if [ -d "$APP_ROOT/var" ] && [ -n "$(ls -A "$APP_ROOT/var" 2>/dev/null)" ]; then
    rsync -a "$APP_ROOT/var/" "$PERSIST_ROOT/var/" || true
  fi
  rm -rf "$APP_ROOT/var"
  ln -s "$PERSIST_ROOT/var" "$APP_ROOT/var"
fi

# uploads
if [ ! -L "$UPLOAD_DIR" ]; then
  mkdir -p "$(dirname "$UPLOAD_DIR")"
  if [ -d "$UPLOAD_DIR" ] && [ -n "$(ls -A "$UPLOAD_DIR" 2>/dev/null)" ]; then
    rsync -a "$UPLOAD_DIR/" "$PERSIST_ROOT/uploads/" || true
  fi
  rm -rf "$UPLOAD_DIR"
  ln -s "$PERSIST_ROOT/uploads" "$UPLOAD_DIR"
fi

# Permissions for Apache/PHP
chown -R www-data:www-data "$PERSIST_ROOT" "$APP_ROOT" || true
chmod -R 775 "$PERSIST_ROOT" "$APP_ROOT/var" "$(dirname "$UPLOAD_DIR")" || true

# Clear+warm cache (non-fatal on first boot)
php "$APP_ROOT/bin/console" cache:clear --env=prod --no-debug || true

# Run DB migrations if DATABASE_URL is set (failsafe: ignore errors on first boot)
if [ -n "${DATABASE_URL:-}" ]; then
  php "$APP_ROOT/bin/console" doctrine:migrations:migrate --no-interaction || true
fi

# IMPORTANT: Do NOT start or touch local mysql here. Railway MySQL is a separate service.

# Hand off to CMD (apachectl -D FOREGROUND)
exec "$@"
