"use client";

import { useState } from "react";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import { formatDateTime } from "@/lib/format";
import type { TimelineEvent } from "@/types/timeline";

export default function TimelinePage() {
  const [requestId, setRequestId] = useState("");
  const [approvalEvents, setApprovalEvents] = useState<TimelineEvent[] | null>(null);
  const [actionEvents, setActionEvents] = useState<TimelineEvent[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = (id: string) => {
    if (!id) return;
    setLoading(true);
    setError(null);
    fetch(`/api/timeline?requestId=${encodeURIComponent(id)}`)
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load the timeline.");
        setApprovalEvents(json.approvalEvents as TimelineEvent[]);
        setActionEvents(json.actionEvents as TimelineEvent[]);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  };

  return (
    <div className="page-shell">
      <div className="page-header">
        <div>
        <h1 className="page-title">Workflow Timeline</h1>
        <p className="page-description">
          Risk / Recommendation &rarr; Approval requested &rarr; Human decision &rarr; Execution validation &rarr;
          DISPATCHED_DEMO / BLOCKED reason.
        </p>
        </div>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          load(requestId);
        }}
        className="surface flex flex-col gap-3 p-3 sm:flex-row"
      >
        <input
          value={requestId}
          onChange={(e) => setRequestId(e.target.value)}
          placeholder="Enter a REQUEST_ID to view its timeline"
          className="field flex-1"
        />
        <button type="submit" className="button-primary shrink-0">
          Load
        </button>
      </form>

      {!requestId && !approvalEvents && (
        <p className="callout text-center">Enter a REQUEST_ID (from the Approval Queue) to see its full structured history.</p>
      )}

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load the timeline from Snowflake." />}

      {approvalEvents && actionEvents && approvalEvents.length === 0 && actionEvents.length === 0 && (
        <p className="rounded-xl border border-amber-200 bg-amber-50/90 p-4 text-sm text-amber-800">No structured events found for &quot;{requestId}&quot;.</p>
      )}

      {approvalEvents && approvalEvents.length > 0 && (
        <div className="surface p-5 sm:p-6">
          <p className="section-heading mb-4">Approval events</p>
          <ul className="relative space-y-0 border-l border-blue-200 pl-5 text-sm text-slate-700">
            {approvalEvents.map((e) => (
              <li key={e.EVENT_ID} className="relative pb-5 last:pb-0 before:absolute before:-left-[1.48rem] before:top-1.5 before:h-2 before:w-2 before:rounded-full before:bg-blue-400 before:shadow-[0_0_10px_rgba(96,165,250,0.65)]">
                <code className="mb-1 block text-xs text-slate-500">{formatDateTime(e.EVENT_AT)}</code>{" "}
                <strong>{e.EVENT_TYPE}</strong> by {e.ACTOR} ({e.ACTOR_ROLE})
                {e.DETAILS ? ` \u2014 ${e.DETAILS}` : ""}
              </li>
            ))}
          </ul>
        </div>
      )}

      {actionEvents && (
        <div className="surface p-5 sm:p-6">
          <p className="section-heading mb-4">Action events</p>
          {actionEvents.length === 0 ? (
            <p className="text-sm text-slate-500">(no action events yet &mdash; this request has not reached dispatch)</p>
          ) : (
            <ul className="relative space-y-0 border-l border-emerald-200 pl-5 text-sm text-slate-700">
              {actionEvents.map((e) => (
                <li key={e.EVENT_ID} className="relative pb-5 last:pb-0 before:absolute before:-left-[1.48rem] before:top-1.5 before:h-2 before:w-2 before:rounded-full before:bg-emerald-400 before:shadow-[0_0_10px_rgba(52,211,153,0.6)]">
                  <code className="mb-1 block text-xs text-slate-500">{formatDateTime(e.EVENT_AT)}</code>{" "}
                  <strong>{e.EVENT_TYPE}</strong> by {e.ACTOR} ({e.ACTOR_ROLE})
                  {e.DETAILS ? ` \u2014 ${e.DETAILS}` : ""}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
