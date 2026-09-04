"use client";

import { useState } from "react";
import { formatDateTime } from "@/lib/format";
import type { ActionCommand } from "@/types/action";

export default function ActionCard({ action }: { action: ActionCommand }) {
  const [open, setOpen] = useState(false);

  return (
    <div className={`surface overflow-hidden transition duration-200 ${open ? "border-blue-300 bg-blue-50/50" : "hover:border-blue-200 hover:bg-white"}`}>
      <button onClick={() => setOpen((v) => !v)} className="flex w-full items-center justify-between gap-4 px-4 py-4 text-left text-sm sm:px-5">
        <span className="min-w-0 font-medium leading-6 text-slate-800">
          {action.ACTION_STATUS} &mdash; {action.ACTION_ID} &mdash; {action.INTERVENTION_TYPE} &mdash;{" "}
          {action.SUPPLIER_ID}/{action.PART_ID}/{action.DESTINATION_PLANT_ID}
        </span>
        <span className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border border-sky-200 bg-sky-50 text-base text-blue-500 transition-transform ${open ? "rotate-180" : ""}`}>{open ? "\u2212" : "+"}</span>
      </button>
      {open && (
        <div className="space-y-1 border-t border-sky-200/70 bg-white/65 px-4 py-4 text-sm leading-6 text-slate-700 sm:px-5">
          <p>
            <strong>Request ID:</strong> {action.REQUEST_ID}
          </p>
          <p>
            <strong>Execution mode:</strong> {action.EXECUTION_MODE}
          </p>
          <p>
            <strong>Dispatched by:</strong> {action.DISPATCHED_BY} ({action.DISPATCHED_ROLE}) at {formatDateTime(action.DISPATCHED_AT)}
          </p>
          <p className="callout mt-3 border-l-2 border-l-sky-400/50 text-xs">
            No SAP/TMS/WMS record was modified and no external operational system was called.
          </p>
          <details className="group mt-3 rounded-lg border border-slate-200 bg-slate-50/70 p-3">
            <summary className="cursor-pointer text-xs font-medium text-slate-500 transition hover:text-blue-700">Command payload</summary>
            <pre className="code-surface mt-3 max-h-64">
              {JSON.stringify(action.COMMAND_PAYLOAD, null, 2)}
            </pre>
          </details>
          <details className="group mt-3 rounded-lg border border-slate-200 bg-slate-50/70 p-3">
            <summary className="cursor-pointer text-xs font-medium text-slate-500 transition hover:text-blue-700">Technical audit detail</summary>
            <p className="mt-3 break-all text-xs text-slate-500">
              APPROVED_SNAPSHOT_HASH: <code>{action.APPROVED_SNAPSHOT_HASH}</code>
            </p>
            <p className="mt-1 break-all text-xs text-slate-500">
              FRESH_EVALUATION_HASH: <code>{action.FRESH_EVALUATION_HASH}</code>
            </p>
          </details>
        </div>
      )}
    </div>
  );
}
