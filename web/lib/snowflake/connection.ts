/**
 * Server-only Snowflake connection singleton.
 *
 * IMPORTANT: this module must never be imported from a Client Component or
 * any code path that ships to the browser. Next.js's `server-only` package
 * enforces this at build time.
 *
 * Credentials are read exclusively from server-side environment variables
 * (never NEXT_PUBLIC_*) and are never logged or returned to callers.
 */
import "server-only";
import snowflake from "snowflake-sdk";
import { readFileSync } from "fs";

let cachedConnection: snowflake.Connection | null = null;
let connectingPromise: Promise<snowflake.Connection> | null = null;

function readRequiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function buildConnectionOptions(): snowflake.ConnectionOptions {
  const base: snowflake.ConnectionOptions = {
    account: readRequiredEnv("SNOWFLAKE_ACCOUNT"),
    username: readRequiredEnv("SNOWFLAKE_USER"),
    role: process.env.SNOWFLAKE_ROLE || undefined,
    warehouse: process.env.SNOWFLAKE_WAREHOUSE || undefined,
    database: process.env.SNOWFLAKE_DATABASE || undefined,
    schema: process.env.SNOWFLAKE_SCHEMA || undefined,
  };

  const authenticator = process.env.SNOWFLAKE_AUTHENTICATOR || "SNOWFLAKE";

  if (authenticator === "SNOWFLAKE_JWT") {
    const keyPath = readRequiredEnv("SNOWFLAKE_PRIVATE_KEY_PATH");
    return {
      ...base,
      authenticator: "SNOWFLAKE_JWT",
      privateKey: readFileSync(keyPath, "utf8"),
      privateKeyPass: process.env.SNOWFLAKE_PRIVATE_KEY_PASSPHRASE || undefined,
    };
  }

  // Fallback: password auth, local development only. Production should use
  // key-pair (SNOWFLAKE_JWT) or another approved non-password mechanism.
  return {
    ...base,
    password: readRequiredEnv("SNOWFLAKE_PASSWORD"),
  };
}

/**
 * Returns a single shared, connected Snowflake connection for the server
 * process. Reused across requests -- never created per-request, and never
 * exposed outside lib/snowflake.
 */
export async function getConnection(): Promise<snowflake.Connection> {
  if (cachedConnection && cachedConnection.isUp()) {
    return cachedConnection;
  }
  if (connectingPromise) {
    return connectingPromise;
  }

  connectingPromise = new Promise((resolve, reject) => {
    let options: snowflake.ConnectionOptions;
    try {
      options = buildConnectionOptions();
    } catch (err) {
      connectingPromise = null;
      console.error("[snowflake] connection config error:", err);
      reject(err instanceof Error ? err : new Error("Snowflake connection configuration is invalid."));
      return;
    }

    const connection = snowflake.createConnection(options);
    connection.connect((err, conn) => {
      connectingPromise = null;
      if (err) {
        // Server-side only (terminal), never sent to the browser. Safe to
        // log in full here -- this never crosses the client boundary.
        console.error("[snowflake] connection failed:", err);
        reject(new Error("Snowflake connection failed."));
        return;
      }
      cachedConnection = conn;
      resolve(conn);
    });
  });

  return connectingPromise;
}
