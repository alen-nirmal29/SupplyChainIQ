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
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-white">Approval Queue</h1>
          <p className="text-sm text-slate-400">
            Sourced directly from WORKFLOW.INTERVENTION_APPROVAL_REQUEST. Human decisions are procedure-mediated.
          </p>
        </div>
        <button onClick={load} className="rounded-md border border-control-border bg-control-panel px-3 py-1.5 text-sm text-slate-200 hover:bg-white/5">
          Refresh
        </button>
      </div>

      <label className="flex items-center gap-2 text-sm text-slate-300">
        <input type="checkbox" checked={showAll} onChange={(e) => setShowAll(e.target.checked)} />
        Show all records (including test artifacts)
      </label>

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load the approval queue from Snowflake." />}
      {!loading && !error && requests.length === 0 && <EmptyState message="No approval requests found." />}

      <div className="space-y-2">
        {requests.map((r) => (
          <ApprovalCard key={r.REQUEST_ID} request={r} isTestArtifact={testArtifactIds.includes(r.REQUEST_ID)} onReviewed={load} />
        ))}
      </div>
    </div>
  );
}
