"use client";

import { useState } from "react";
import StatusBadge from "@/components/ui/StatusBadge";
import { formatDateTime } from "@/lib/format";
import type { ApprovalRequest, ReviewDecision } from "@/types/approval";

interface ApprovalCardProps {
  request: ApprovalRequest;
  isTestArtifact: boolean;
  onReviewed: () => void;
}

const EXEC_LABEL: Record<string, string> = {
  NOT_DISPATCHED: "",
  DISPATCH_CLAIMED: "Dispatch claimed",
  DISPATCHED_DEMO: "Dispatched (demo)",
};

export default function ApprovalCard({ request, isTestArtifact, onReviewed }: ApprovalCardProps) {
  const [open, setOpen] = useState(false);
  const [pendingDecision, setPendingDecision] = useState<ReviewDecision | null>(null);
  const [comment, setComment] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submitDecision = async () => {
    if (!pendingDecision) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch(`/api/approvals/${encodeURIComponent(request.REQUEST_ID)}/review`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ decision: pendingDecision, comment: comment || null }),
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.error ?? "The review procedure could not be called.");
      setPendingDecision(null);
      setComment("");
      onReviewed();
    } catch (err) {
      setError(err instanceof Error ? err.message : "The review procedure could not be called.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="rounded-lg border border-control-border bg-control-panel">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left"
      >
        <div className="flex flex-wrap items-center gap-2 text-sm">
          {isTestArtifact && <span className="text-xs text-slate-500">[Pre-fix test artifact]</span>}
          <StatusBadge status={request.REQUEST_STATUS} />
          {EXEC_LABEL[request.EXECUTION_STATUS] && <StatusBadge status={request.EXECUTION_STATUS} label={EXEC_LABEL[request.EXECUTION_STATUS]} />}
          <span className="text-slate-200">{request.REQUEST_ID}</span>
          <span className="text-slate-400">
            {request.SUPPLIER_NAME} / {request.PART_DESCRIPTION} / {request.PLANT_NAME} &mdash;{" "}
            {request.SELECTED_INTERVENTION_TYPE} (rank {request.RECOMMENDATION_RANK})
          </span>
        </div>
        <span className="text-slate-500">{open ? "\u2212" : "+"}</span>
      </button>

      {open && (
        <div className="border-t border-control-border px-4 py-3 text-sm text-slate-300">
          <p>
            <strong>Requested by:</strong> {request.REQUESTED_BY} ({request.REQUESTED_ROLE}) at{" "}
            {formatDateTime(request.REQUESTED_AT)}
          </p>
          {request.APPROVED_OR_REJECTED_BY && (
            <p>
              <strong>Decision by:</strong> {request.APPROVED_OR_REJECTED_BY} at {formatDateTime(request.DECISION_AT)}
            </p>
          )}
          {request.DECISION_COMMENT && (
            <p>
              <strong>Comment:</strong> {request.DECISION_COMMENT}
            </p>
          )}
          {request.ACTION_ID && (
            <p>
              <strong>Action ID:</strong> {request.ACTION_ID}
            </p>
          )}

          <details className="mt-2">
            <summary className="cursor-pointer text-xs text-slate-500">
              Recommendation snapshot (immutable, at time of submission)
            </summary>
            <pre className="mt-1 max-h-64 overflow-auto rounded bg-black/30 p-2 text-xs">
              {JSON.stringify(request.RECOMMENDATION_SNAPSHOT, null, 2)}
            </pre>
            <p className="mt-1 text-xs text-slate-500">
              RECOMMENDATION_HASH: <code>{request.RECOMMENDATION_HASH}</code>
            </p>
          </details>

          {request.REQUEST_STATUS === "PENDING" && (
            <div className="mt-4 space-y-2">
              {!pendingDecision ? (
                <div className="flex gap-2">
                  <button onClick={() => setPendingDecision("APPROVE")} className="rounded-md bg-emerald-600/80 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-600">
                    Approve
                  </button>
                  <button onClick={() => setPendingDecision("REJECT")} className="rounded-md bg-red-600/80 px-3 py-1.5 text-xs font-medium text-white hover:bg-red-600">
                    Reject
                  </button>
                  <button onClick={() => setPendingDecision("CANCEL")} className="rounded-md bg-slate-600/80 px-3 py-1.5 text-xs font-medium text-white hover:bg-slate-600">
                    Cancel
                  </button>
                </div>
              ) : (
                <div className="rounded-md border border-control-border bg-black/20 p-3">
                  <p className="mb-2 text-sm">
                    Confirm <strong>{pendingDecision}</strong> for request <code>{request.REQUEST_ID}</code>?
                  </p>
                  <input
                    value={comment}
                    onChange={(e) => setComment(e.target.value)}
                    placeholder="Optional comment"
                    className="mb-2 w-full rounded-md border border-control-border bg-control-panel px-2 py-1.5 text-sm text-white placeholder:text-slate-500"
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={submitDecision}
                      disabled={submitting}
                      className="rounded-md bg-control-accent px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-600 disabled:opacity-50"
                    >
                      {submitting ? "Submitting..." : `Confirm ${pendingDecision.toLowerCase()}`}
                    </button>
                    <button
                      onClick={() => {
                        setPendingDecision(null);
                        setError(null);
                      }}
                      className="rounded-md border border-control-border px-3 py-1.5 text-xs text-slate-300 hover:bg-white/5"
                    >
                      Dismiss
                    </button>
                  </div>
                  {error && <p className="mt-2 text-xs text-red-300">{error}</p>}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
