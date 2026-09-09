FROM denoland/deno:2.1.4

# Run as non-root user
USER deno

WORKDIR /app

# Copy shared utilities and function code
COPY --chown=deno:deno shared/ ./shared/
COPY --chown=deno:deno functions/ ./functions/
COPY --chown=deno:deno server.ts ./server.ts
COPY --chown=deno:deno deno.json ./deno.json

# Cache dependencies
RUN deno cache server.ts

# Type check at build time as well as in CI (US-EDGE002). `deno run` in the CMD
# below strips types without checking them, so without this a type error that
# slipped past review — like the ReferenceError on the escalation SMS path in
# US-EDGE001 — becomes a runtime failure in production instead of a failed
# build. Dependencies are already cached above, so this needs no network.
RUN deno check server.ts

EXPOSE 9000

# Health check (using Deno fetch since curl is not available in the Deno image)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD deno eval "const r = await fetch('http://localhost:9000/health'); const d = await r.json(); if (d.status !== 'ok') Deno.exit(1);" || exit 1

CMD ["deno", "run", "--allow-net", "--allow-env", "--allow-read=/app", "server.ts"]
