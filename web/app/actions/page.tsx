"use client";

import { useEffect, useState } from "react";
import LoadingState from "@/components/ui/LoadingState";
import ErrorState from "@/components/ui/ErrorState";
import EmptyState from "@/components/ui/EmptyState";
import ActionCard from "@/components/actions/ActionCard";
import type { ActionCommand } from "@/types/action";

export default function ActionsPage() {
  const [actions, setActions] = useState<ActionCommand[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    setLoading(true);
    setError(null);
    fetch("/api/actions")
      .then(async (res) => {
        const json = await res.json();
        if (!res.ok) throw new Error(json.error ?? "Failed to load actions.");
        setActions(json.actions as ActionCommand[]);
      })
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  };

  useEffect(load, []);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-white">Actions</h1>
          <p className="text-sm text-slate-400">
            Sourced directly from ACTION.INTERVENTION_ACTION_COMMAND. Dispatch is always Agent-tool-mediated (never a
            direct button in this UI).
          </p>
        </div>
        <button onClick={load} className="rounded-md border border-control-border bg-control-panel px-3 py-1.5 text-sm text-slate-200 hover:bg-white/5">
          Refresh
        </button>
      </div>

      {loading && <LoadingState />}
      {error && <ErrorState message="Could not load actions from Snowflake." />}
      {!loading && !error && actions.length === 0 && (
        <EmptyState message='No demo actions have been dispatched yet. Use Ask SupplyChainIQ: "Execute approved request <REQUEST_ID>."' />
      )}

      <div className="space-y-2">
        {actions.map((a) => (
          <ActionCard key={a.ACTION_ID} action={a} />
        ))}
      </div>
    </div>
  );
}
