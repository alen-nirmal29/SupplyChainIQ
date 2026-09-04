"use client";

import { useCallback, useEffect, useState } from "react";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import EmptyState from "@/components/ui/EmptyState";
import ApprovalCard from "@/components/approvals/ApprovalCard";
import type { ApprovalRequest } from "@/types/approval";

export default function ApprovalsPage() {
  const [requests, setRequests] = useState<ApprovalRequest[]>([]);
  const [testArtifactIds, setTestArtifactIds] = useState<string[]>([]);
  const [showAll, setShowAll] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    setError(null);
    fetch(`/api/approvals?includeTestArtifacts=${showAll}`)
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load the approval queue.");
        setRequests(json.requests as ApprovalRequest[]);
        setTestArtifactIds(json.knownTestArtifactIds as string[]);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, [showAll]);

  useEffect(load, [load]);

  return (
    <div className="page-shell">
      <div className="page-header">
        <div>
          <h1 className="page-title">Approval Queue</h1>
          <p className="page-description">
            Sourced directly from WORKFLOW.INTERVENTION_APPROVAL_REQUEST. Human decisions are procedure-mediated.
          </p>
        </div>
        <button onClick={load} className="button-secondary shrink-0">
          Refresh
        </button>
      </div>

      <label className="surface flex w-fit cursor-pointer items-center gap-3 px-4 py-3 text-sm text-slate-700 transition hover:border-blue-300 hover:text-blue-700">
        <input type="checkbox" checked={showAll} onChange={(e) => setShowAll(e.target.checked)} className="h-4 w-4 rounded border-slate-300 bg-white text-control-accent accent-blue-500" />
        Show all records (including test artifacts)
      </label>

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load the approval queue from Snowflake." />}
      {!loading && !error && requests.length === 0 && <EmptyState message="No approval requests found." />}

      <div className="space-y-3">
        {requests.map((r) => (
          <ApprovalCard key={r.REQUEST_ID} request={r} isTestArtifact={testArtifactIds.includes(r.REQUEST_ID)} onReviewed={load} />
        ))}
      </div>
    </div>
  );
}
