"use client";

import { useState } from "react";
import { formatDateTime } from "@/lib/format";
import type { ActionCommand } from "@/types/action";

export default function ActionCard({ action }: { action: ActionCommand }) {
  const [open, setOpen] = useState(false);

  return (
    <div className="rounded-lg border border-control-border bg-control-panel">
      <button onClick={() => setOpen((v) => !v)} className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left text-sm">
        <span className="text-slate-200">
          {action.ACTION_STATUS} &mdash; {action.ACTION_ID} &mdash; {action.INTERVENTION_TYPE} &mdash;{" "}
          {action.SUPPLIER_ID}/{action.PART_ID}/{action.DESTINATION_PLANT_ID}
        </span>
        <span className="text-slate-500">{open ? "\u2212" : "+"}</span>
      </button>
      {open && (
        <div className="border-t border-control-border px-4 py-3 text-sm text-slate-300">
          <p>
            <strong>Request ID:</strong> {action.REQUEST_ID}
          </p>
          <p>
            <strong>Execution mode:</strong> {action.EXECUTION_MODE}
          </p>
          <p>
            <strong>Dispatched by:</strong> {action.DISPATCHED_BY} ({action.DISPATCHED_ROLE}) at {formatDateTime(action.DISPATCHED_AT)}
          </p>
          <p className="mt-2 rounded-md border border-control-border bg-black/20 px-3 py-2 text-xs text-slate-400">
            No SAP/TMS/WMS record was modified and no external operational system was called.
          </p>
          <details className="mt-2">
            <summary className="cursor-pointer text-xs text-slate-500">Command payload</summary>
            <pre className="mt-1 max-h-64 overflow-auto rounded bg-black/30 p-2 text-xs">
              {JSON.stringify(action.COMMAND_PAYLOAD, null, 2)}
            </pre>
          </details>
          <details className="mt-2">
            <summary className="cursor-pointer text-xs text-slate-500">Technical audit detail</summary>
            <p className="mt-1 text-xs text-slate-500">
              APPROVED_SNAPSHOT_HASH: <code>{action.APPROVED_SNAPSHOT_HASH}</code>
            </p>
            <p className="text-xs text-slate-500">
              FRESH_EVALUATION_HASH: <code>{action.FRESH_EVALUATION_HASH}</code>
            </p>
          </details>
        </div>
      )}
    </div>
  );
}
