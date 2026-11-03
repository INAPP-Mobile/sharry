#!/bin/bash
# Sharry Railway wrapper entrypoint.
#
# Sharry reads every setting from a SHARRY_* environment variable
# first and falls back to the conf file shipped in the distribution
# (verified in upstream ConfigValues.scala: senv(...).or(hocon(...))).
# This script only derives the two values that depend on the live
# deployment, then starts the upstream launcher (which honours
# JAVA_OPTS for the heap cap set in the Dockerfile):
# - PORT: Railway injects PORT at runtime; Sharry's bind port
#   defaults to 9090, so export SHARRY_BIND_PORT=$PORT (and bind
#   all interfaces, since the shipped default is localhost).
# - BASE URL: share links, cookies and websockets are built from
#   base-url. Derive it from RAILWAY_PUBLIC_DOMAIN when present
#   (https://<domain>); never bake a template expression for it —
#   a baked https://${{RAILWAY_PUBLIC_DOMAIN}} resolved to a bare
#   https:// on the Spliit run and broke every page render.
# - SECRETS: ADMIN_PASSWORD and SERVER_SECRET arrive as service
#   variables (generated template variables). They are mapped to
#   the SHARRY_* names Sharry actually reads. If ADMIN_PASSWORD is
#   unset, the log says so loudly: the fixed account would still
#   be enabled with an empty password check, which must never ship
#   silently. (Fixed auth with a password never matches an empty
#   one, but fail loud anyway.)
# - DATA: /data is the single Railway volume. The H2 database file
#   (jdbc:h2:/data/sharry, baked in the Dockerfile) and the default
#   database file store both live there, so uploads, shares and
#   accounts survive restarts and redeploys.
set -e

mkdir -p /data

export SHARRY_BIND_ADDRESS="0.0.0.0"
export SHARRY_BIND_PORT="${PORT:-9090}"

if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
  export SHARRY_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
fi

if [ -n "$ADMIN_PASSWORD" ]; then
  export SHARRY_BACKEND_AUTH_FIXED_PASSWORD="$ADMIN_PASSWORD"
else
  echo "Sharry: WARNING ADMIN_PASSWORD unset - set it before sharing the URL."
fi

if [ -n "$SERVER_SECRET" ]; then
  export SHARRY_BACKEND_AUTH_SERVER_SECRET="$SERVER_SECRET"
else
  echo "Sharry: WARNING SERVER_SECRET unset - auth tokens would use the public upstream default; set it."
fi

echo "Sharry: binding 0.0.0.0:${SHARRY_BIND_PORT}, base-url ${SHARRY_BASE_URL:-<upstream default>}, jdbc /data/sharry (H2)"
exec /opt/sharry/bin/sharry-restserver
