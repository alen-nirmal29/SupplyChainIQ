/**
 * Public-demo-mode guard.
 *
 * When PUBLIC_DEMO_MODE=true, every mutating route handler must call
 * `assertMutationsAllowed()` before doing anything else. This is a
 * server-side enforcement point -- it does not rely on the UI hiding
 * buttons, and it cannot be bypassed by calling the API directly.
 */
import "server-only";

export function isPublicDemoMode(): boolean {
  return process.env.PUBLIC_DEMO_MODE === "true";
}

export class MutationsDisabledError extends Error {
  constructor() {
    super("Mutations are disabled in public demo mode.");
    this.name = "MutationsDisabledError";
  }
}

/** Throws MutationsDisabledError if PUBLIC_DEMO_MODE=true. Call this first
 * in every route handler that writes to Snowflake (approval review,
 * dispatch, or any future write path). */
export function assertMutationsAllowed(): void {
  if (isPublicDemoMode()) {
    throw new MutationsDisabledError();
  }
}
