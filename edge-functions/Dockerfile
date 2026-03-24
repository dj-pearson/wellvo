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

EXPOSE 9000

# Health check (using Deno fetch since curl is not available in the Deno image)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD deno eval "const r = await fetch('http://localhost:9000/health'); const d = await r.json(); if (d.status !== 'ok') Deno.exit(1);" || exit 1

CMD ["deno", "run", "--allow-net", "--allow-env", "--allow-read=/app", "server.ts"]
