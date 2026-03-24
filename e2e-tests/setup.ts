import { config } from "dotenv";
import { resolve } from "path";

// Load .env file from e2e-tests directory (if it exists)
config({ path: resolve(__dirname, ".env") });

// Trust self-hosted Supabase TLS certificate (Coolify/Let's Encrypt)
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
