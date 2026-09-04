"use client";

import { useState } from "react";
import type { AgentMessage, AgentTurnResponse } from "@/types/agent";

const STARTER_QUESTIONS = [
  "What can we do about the High-Precision Hydraulic Control Valve Assembly Type 104 shortage at Pune Assembly Plant caused by Pinnacle Industries? Compare the options and recommend the best intervention.",
  "Why are deliveries for P104 at Pune Assembly Plant at risk?",
  "What is Pinnacle Industries' on-time delivery performance?",
  "What does the supplier SLA say about expedite terms?",
];

export default function AgentChat() {
  const [messages, setMessages] = useState<AgentMessage[]>([]);
  const [threadId, setThreadId] = useState<number | null>(null);
  const [parentMessageId, setParentMessageId] = useState<number | null>(null);
  const [hadRecommendation, setHadRecommendation] = useState(false);
  const [submitShortcutUsed, setSubmitShortcutUsed] = useState(false);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);

  const send = async (text: string) => {
    setMessages((prev) => [...prev, { role: "user", content: text }]);
    setSending(true);
    try {
      const res = await fetch("/api/agent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, threadId, parentMessageId }),
      });
      const result = (await res.json()) as AgentTurnResponse;

      if (!res.ok || result.error) {
        setMessages((prev) => [...prev, { role: "assistant", content: null, error: result.error ?? "Agent call failed." }]);
        return;
      }

      setThreadId(result.threadId ?? threadId);
      setParentMessageId(result.assistantMessageId ?? parentMessageId);
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: result.text, toolsUsed: result.toolsUsed, runId: result.runId ?? undefined },
      ]);
      if (result.toolsUsed.includes("evaluate_supply_chain_interventions")) {
        setHadRecommendation(true);
      }
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-control-border bg-control-panel p-4">
        <div className="mb-2 text-sm font-medium text-white">
          Operational recommendation &ne; contractual authorization
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <div className="text-xs uppercase text-slate-500">Operational recommendation</div>
            <div className="text-sm text-slate-200">Road &middot; 3 days &middot; 1.6&times; operational cost factor</div>
          </div>
          <div>
            <div className="text-xs uppercase text-slate-500">Contractual / SLA evidence</div>
            <div className="text-sm text-slate-200">Air &middot; 4 days &middot; 2.6&times; &middot; see supplier document search</div>
          </div>
        </div>
        <p className="mt-2 text-xs text-slate-500">
          This operational recommendation is not automatically contractually authorized, and human approval does not
          establish contractual authorization either. Confirm expedite-lane terms against the supplier SLA if
          contractual compliance matters.
        </p>
      </div>

      {messages.length === 0 && (
        <div>
          <p className="mb-2 text-sm font-medium text-slate-300">Try asking:</p>
          <div className="flex flex-col gap-2">
            {STARTER_QUESTIONS.map((q) => (
              <button
                key={q}
                onClick={() => send(q)}
                className="rounded-md border border-control-border bg-control-panel px-3 py-2 text-left text-sm text-slate-200 hover:bg-white/5"
              >
                {q}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="space-y-3">
        {messages.map((msg, i) => (
          <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
            <div
              className={`max-w-2xl rounded-lg px-4 py-3 text-sm ${
                msg.role === "user" ? "bg-control-accent text-white" : "border border-control-border bg-control-panel text-slate-200"
              }`}
            >
              {msg.error ? (
                <>
                  <p className="text-red-300">SupplyChainIQ couldn&apos;t complete that request. Please try rephrasing or try again.</p>
                </>
              ) : (
                <>
                  <p className="whitespace-pre-wrap">{msg.content}</p>
                  {msg.toolsUsed && msg.toolsUsed.length > 0 && (
                    <details className="mt-2 text-xs text-slate-400">
                      <summary className="cursor-pointer">Tools used</summary>
                      <ul className="mt-1 list-disc pl-4">
                        {msg.toolsUsed.map((t) => (
                          <li key={t}>
                            <code>{t}</code>
                          </li>
                        ))}
                      </ul>
                      {msg.runId && <p className="mt-1">run_id: {msg.runId}</p>}
                    </details>
                  )}
                </>
              )}
            </div>
          </div>
        ))}
      </div>

      {hadRecommendation && !submitShortcutUsed && (
        <button
          onClick={() => {
            send("Submit the recommended option for approval.");
            setSubmitShortcutUsed(true);
          }}
          className="rounded-md border border-control-border bg-control-panel px-3 py-2 text-sm text-slate-200 hover:bg-white/5"
        >
          Submit the recommended option for approval
        </button>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!input.trim() || sending) return;
          send(input.trim());
          setInput("");
        }}
        className="flex gap-2"
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Ask SupplyChainIQ..."
          disabled={sending}
          className="flex-1 rounded-md border border-control-border bg-control-panel px-3 py-2 text-sm text-white placeholder:text-slate-500 focus:outline-none focus:ring-1 focus:ring-control-accent"
        />
        <button
          type="submit"
          disabled={sending || !input.trim()}
          className="rounded-md bg-control-accent px-4 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:opacity-50"
        >
          {sending ? "Sending..." : "Send"}
        </button>
      </form>
    </div>
  );
}
