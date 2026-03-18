FROM denoland/deno:2.1.4

WORKDIR /app

# Copy shared utilities and function code
COPY shared/ ./shared/
COPY functions/ ./functions/
COPY server.ts ./server.ts
COPY deno.json ./deno.json

# Cache dependencies
RUN deno cache server.ts

EXPOSE 9000

# Run the edge functions server
CMD ["deno", "run", "--allow-net", "--allow-env", "--allow-read", "server.ts"]
