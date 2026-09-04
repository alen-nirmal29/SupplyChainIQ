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
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-white">Workflow Timeline</h1>
        <p className="text-sm text-slate-400">
          Risk / Recommendation &rarr; Approval requested &rarr; Human decision &rarr; Execution validation &rarr;
          DISPATCHED_DEMO / BLOCKED reason.
        </p>
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          load(requestId);
        }}
        className="flex gap-2"
      >
        <input
          value={requestId}
          onChange={(e) => setRequestId(e.target.value)}
          placeholder="Enter a REQUEST_ID to view its timeline"
          className="flex-1 rounded-md border border-control-border bg-control-panel px-3 py-2 text-sm text-white placeholder:text-slate-500"
        />
        <button type="submit" className="rounded-md bg-control-accent px-4 py-2 text-sm font-medium text-white hover:bg-blue-600">
          Load
        </button>
      </form>

      {!requestId && !approvalEvents && (
        <p className="text-sm text-slate-500">Enter a REQUEST_ID (from the Approval Queue) to see its full structured history.</p>
      )}

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load the timeline from Snowflake." />}

      {approvalEvents && actionEvents && approvalEvents.length === 0 && actionEvents.length === 0 && (
        <p className="text-sm text-yellow-300">No structured events found for &quot;{requestId}&quot;.</p>
      )}

      {approvalEvents && approvalEvents.length > 0 && (
        <div>
          <p className="mb-1 text-sm font-medium text-slate-200">Approval events</p>
          <ul className="space-y-1 text-sm text-slate-300">
            {approvalEvents.map((e) => (
              <li key={e.EVENT_ID}>
                <code className="text-xs text-slate-500">{formatDateTime(e.EVENT_AT)}</code>{" "}
                <strong>{e.EVENT_TYPE}</strong> by {e.ACTOR} ({e.ACTOR_ROLE})
                {e.DETAILS ? ` \u2014 ${e.DETAILS}` : ""}
              </li>
            ))}
          </ul>
        </div>
      )}

      {actionEvents && (
        <div>
          <p className="mb-1 text-sm font-medium text-slate-200">Action events</p>
          {actionEvents.length === 0 ? (
            <p className="text-sm text-slate-500">(no action events yet &mdash; this request has not reached dispatch)</p>
          ) : (
            <ul className="space-y-1 text-sm text-slate-300">
              {actionEvents.map((e) => (
                <li key={e.EVENT_ID}>
                  <code className="text-xs text-slate-500">{formatDateTime(e.EVENT_AT)}</code>{" "}
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
