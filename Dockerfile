# Sharry on Railway — wrapper around the pinned upstream image.
#
# Why a wrapper at all (house style: bake constants, keep the deploy
# form zero-field, and survive Railway's root-owned volumes):
# - PORT: Sharry binds to whatever sharry.restserver.bind.port says
#   (default 9090, from the conf file shipped in the distribution).
#   It does NOT read Railway's injected PORT on its own, but every
#   setting is overridable with a SHARRY_* environment variable
#   (verified in upstream ConfigValues.scala: env wins over HOCON).
#   entrypoint.sh therefore exports SHARRY_BIND_PORT=$PORT and
#   SHARRY_BIND_ADDRESS=0.0.0.0 on every boot.
# - BASE URL: share links, cookies and websockets are built from
#   sharry.restserver.base-url. entrypoint.sh derives it from
#   Railway's RAILWAY_PUBLIC_DOMAIN on every boot (https://...),
#   instead of baking a template expression into a variable (the
#   Spliit run proved a baked https://${{RAILWAY_PUBLIC_DOMAIN}}
#   resolves to a bare https:// and breaks rendering).
# - DATABASE: upstream's default is an H2 file database
#   (jdbc:h2:... in the shipped conf; the H2 driver jar is inside
#   the distribution, verified in the v1.17.0 release zip). The
#   wrapper points it at /data/sharry on the single Railway volume
#   with PostgreSQL compatibility mode, so no companion database
#   service is needed. Files use the default database store, so
#   uploads live in the same H2 file — one volume holds everything.
# - ACCOUNTS: upstream's shipped conf leaves signup "open" and no
#   fixed account. The wrapper closes signup and enables the fixed
#   auth module instead: the fixed user is created as an admin on
#   first login (verified in upstream FixedAuth.scala: addAccount
#   with admin = true). ADMIN_PASSWORD is the generated template
#   variable; SERVER_SECRET signs auth tokens and must be unique
#   per deployment (the shipped default is public in the repo, so
#   leaving it would let anyone forge tokens) — it is also a
#   generated template variable. Both are passed through as plain
#   service variables; Sharry reads them via SHARRY_* env vars.
# - JVM HEAP: the launcher script honours JAVA_OPTS (verified in
#   the v1.17.0 launcher script), so the wrapper caps the heap at
#   512 MB — the JVM would otherwise size it from host memory,
#   not the container limit.
# - USER root: Railway mounts /data root-owned; upstream runs as
#   uid 10001, which would crash-loop on EACCES writing the H2
#   file. The wrapper runs as root, so /data is writable.
# - No Docker HEALTHCHECK: rely on Railway's external
#   healthcheckPath (/api/v2/open/info/version is upstream's own
#   unauthenticated version endpoint, used by its docker-compose
#   healthcheck).
#
# Upstream: Sharry v1.17.0 (GPL-3.0), image pinned by manifest
# digest, verified 2026-11-03 via the Docker Hub registry API
# (multi-arch index digest below; amd64 image digest
# sha256:5657baf35e6f34022a8539f00adc84e928ed7bdfeadcf2ae2fe691f04fd1cc4e).

FROM eikek0/sharry:1.17.0@sha256:e70cf90528c1e1d8c991e0f3c1e5e76a121e68152e262cbeebdb0de84ca8b4f6

USER root

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Baked constants: H2 database on the volume, filesystem-independent
# file store, closed signup, fixed admin account enabled. The two
# secrets (ADMIN_PASSWORD, SERVER_SECRET) arrive as service
# variables, not baked values.
ENV SHARRY_BACKEND_JDBC_URL="jdbc:h2:/data/sharry;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE" \
    SHARRY_BACKEND_JDBC_USER="sa" \
    SHARRY_BACKEND_AUTH_FIXED_ENABLED="true" \
    SHARRY_BACKEND_AUTH_FIXED_USER="admin" \
    SHARRY_BACKEND_SIGNUP_MODE="closed" \
    SHARRY_BACKEND_AUTH_INTERNAL_ENABLED="true" \
    JAVA_OPTS="-Xmx512m"

EXPOSE 9090

ENTRYPOINT ["/entrypoint.sh"]
