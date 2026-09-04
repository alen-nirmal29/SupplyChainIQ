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
    <div className={`surface overflow-hidden transition duration-200 ${open ? "border-violet-300 bg-violet-50/40" : "hover:border-violet-200 hover:bg-white"}`}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center justify-between gap-4 px-4 py-4 text-left sm:px-5"
      >
        <div className="flex min-w-0 flex-wrap items-center gap-2 text-sm leading-6">
          {isTestArtifact && <span className="text-xs text-slate-500">[Pre-fix test artifact]</span>}
          <StatusBadge status={request.REQUEST_STATUS} />
          {EXEC_LABEL[request.EXECUTION_STATUS] && <StatusBadge status={request.EXECUTION_STATUS} label={EXEC_LABEL[request.EXECUTION_STATUS]} />}
          <span className="font-mono text-xs font-medium text-slate-700">{request.REQUEST_ID}</span>
          <span className="text-slate-500">
            {request.SUPPLIER_NAME} / {request.PART_DESCRIPTION} / {request.PLANT_NAME} &mdash;{" "}
            {request.SELECTED_INTERVENTION_TYPE} (rank {request.RECOMMENDATION_RANK})
          </span>
        </div>
        <span className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border border-violet-200 bg-violet-50 text-base text-violet-500 transition-transform ${open ? "rotate-180" : ""}`}>{open ? "\u2212" : "+"}</span>
      </button>

      {open && (
        <div className="space-y-1 border-t border-violet-200/70 bg-white/65 px-4 py-4 text-sm leading-6 text-slate-700 sm:px-5">
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

          <details className="mt-3 rounded-lg border border-slate-200 bg-slate-50/70 p-3">
            <summary className="cursor-pointer text-xs font-medium text-slate-500 transition hover:text-blue-700">
              Recommendation snapshot (immutable, at time of submission)
            </summary>
            <pre className="code-surface mt-3 max-h-64">
              {JSON.stringify(request.RECOMMENDATION_SNAPSHOT, null, 2)}
            </pre>
            <p className="mt-2 break-all text-xs text-slate-500">
              RECOMMENDATION_HASH: <code>{request.RECOMMENDATION_HASH}</code>
            </p>
          </details>

          {request.REQUEST_STATUS === "PENDING" && (
            <div className="mt-5 space-y-3">
              {!pendingDecision ? (
                <div className="flex flex-wrap gap-2">
                  <button onClick={() => setPendingDecision("APPROVE")} className="inline-flex min-h-9 items-center rounded-lg bg-emerald-500/90 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-emerald-500">
                    Approve
                  </button>
                  <button onClick={() => setPendingDecision("REJECT")} className="inline-flex min-h-9 items-center rounded-lg bg-red-500/90 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-red-500">
                    Reject
                  </button>
                  <button onClick={() => setPendingDecision("CANCEL")} className="inline-flex min-h-9 items-center rounded-lg bg-slate-600/80 px-3.5 py-2 text-xs font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-slate-600">
                    Cancel
                  </button>
                </div>
              ) : (
                <div className="rounded-xl border border-blue-200 bg-blue-50/70 p-4">
                  <p className="mb-2 text-sm">
                    Confirm <strong>{pendingDecision}</strong> for request <code>{request.REQUEST_ID}</code>?
                  </p>
                  <input
                    value={comment}
                    onChange={(e) => setComment(e.target.value)}
                    placeholder="Optional comment"
                    className="field mb-3 w-full"
                  />
                  <div className="flex gap-2">
                    <button
                      onClick={submitDecision}
                      disabled={submitting}
                      className="button-primary min-h-9 px-3.5 py-1.5 text-xs"
                    >
                      {submitting ? "Submitting..." : `Confirm ${pendingDecision.toLowerCase()}`}
                    </button>
                    <button
                      onClick={() => {
                        setPendingDecision(null);
                        setError(null);
                      }}
                      className="button-secondary min-h-9 px-3.5 py-1.5 text-xs"
                    >
                      Dismiss
                    </button>
                  </div>
                  {error && <p className="mt-2 text-xs text-red-700">{error}</p>}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
