/**
 * Server-only parameterized query / procedure-call helpers.
 *
 * Every caller MUST pass SQL text with `?` placeholders and a `binds`
 * array -- never string-concatenate untrusted input into SQL. Route
 * handlers and Server Components are the only allowed callers; this
 * module is never imported into a Client Component.
 */
import "server-only";
import { getConnection } from "./connection";

export type SqlBind = string | number | boolean | null;

/**
 * Runs a parameterized SELECT/utility statement and returns plain rows.
 * `sqlText` must use `?` placeholders bound positionally via `binds`.
 */
export async function query<T = Record<string, unknown>>(
  sqlText: string,
  binds: SqlBind[] = []
): Promise<T[]> {
  const connection = await getConnection();
  return new Promise<T[]>((resolve, reject) => {
    connection.execute({
      sqlText,
      binds,
      complete: (err, _stmt, rows) => {
        if (err) {
          console.error("[snowflake] query failed:", err, "\nSQL:", sqlText);
          reject(new Error("Snowflake query failed."));
          return;
        }
        resolve((rows as T[]) ?? []);
      },
    });
  });
}

/**
 * Calls an existing governed Snowflake stored procedure by fully-qualified
 * name with positional parameters, and returns its parsed result. Only a
 * fixed, known set of procedure names should ever be passed here from
 * route handlers -- never a name derived from unsanitized user input.
 */
export async function callProcedure<T = unknown>(
  procedureFqn: string,
  params: SqlBind[]
): Promise<T> {
  const placeholders = params.map(() => "?").join(", ");
  const rows = await query<Record<string, unknown>>(
    `CALL ${procedureFqn}(${placeholders})`,
    params
  );
  const first = rows[0];
  if (!first) {
    throw new Error("Procedure returned no result.");
  }
  const rawValue = Object.values(first)[0];
  if (typeof rawValue === "string") {
    try {
      return JSON.parse(rawValue) as T;
    } catch {
      return rawValue as unknown as T;
    }
  }
  return rawValue as T;
}
