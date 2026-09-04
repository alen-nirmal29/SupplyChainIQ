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
    <div className="space-y-5">
      <div className="surface relative overflow-hidden border-violet-200 p-5 sm:p-6">
        <div className="absolute -right-12 -top-12 h-36 w-36 rounded-full bg-violet-300/30 blur-3xl" />
        <div className="relative mb-4 text-sm font-semibold text-[#10213f]">
          Operational recommendation &ne; contractual authorization
        </div>
        <div className="relative grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="rounded-lg border border-emerald-200 bg-emerald-50/65 p-4">
            <div className="text-[0.68rem] font-semibold uppercase tracking-[0.09em] text-emerald-700">Operational recommendation</div>
            <div className="mt-1.5 text-sm text-slate-700">Road &middot; 3 days &middot; 1.6&times; operational cost factor</div>
          </div>
          <div className="rounded-lg border border-violet-200 bg-violet-50/70 p-4">
            <div className="text-[0.68rem] font-semibold uppercase tracking-[0.09em] text-violet-700">Contractual / SLA evidence</div>
            <div className="mt-1.5 text-sm text-slate-700">Air &middot; 4 days &middot; 2.6&times; &middot; see supplier document search</div>
          </div>
        </div>
        <p className="relative mt-4 text-xs leading-5 text-slate-500">
          This operational recommendation is not automatically contractually authorized, and human approval does not
          establish contractual authorization either. Confirm expedite-lane terms against the supplier SLA if
          contractual compliance matters.
        </p>
      </div>

      {messages.length === 0 && (
        <div className="surface p-4 sm:p-5">
          <p className="mb-3 text-sm font-medium text-slate-700">Try asking:</p>
          <div className="grid grid-cols-1 gap-2 lg:grid-cols-2">
            {STARTER_QUESTIONS.map((q) => (
              <button
                key={q}
                onClick={() => send(q)}
                className="rounded-lg border border-sky-200 bg-sky-50/50 px-4 py-3 text-left text-sm leading-6 text-slate-700 transition duration-200 hover:-translate-y-0.5 hover:border-blue-300 hover:bg-blue-50 hover:text-blue-800"
              >
                {q}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="space-y-4 py-1">
        {messages.map((msg, i) => (
          <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
            <div
              className={`max-w-2xl rounded-2xl px-4 py-3 text-sm leading-6 shadow-lg shadow-black/10 sm:px-5 ${
                msg.role === "user" ? "rounded-br-md bg-gradient-to-br from-blue-500 to-indigo-600 text-white" : "surface rounded-bl-md text-slate-700"
              }`}
            >
              {msg.error ? (
                <>
                  <p className="text-red-700">SupplyChainIQ couldn&apos;t complete that request. Please try rephrasing or try again.</p>
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
          className="button-secondary"
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
        className="surface sticky bottom-3 flex gap-2 border-blue-200 p-2.5 shadow-[0_20px_60px_-24px_rgba(43,74,112,0.38)]"
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Ask SupplyChainIQ..."
          disabled={sending}
          className="field min-w-0 flex-1 border-transparent bg-white/70"
        />
        <button
          type="submit"
          disabled={sending || !input.trim()}
          className="button-primary shrink-0"
        >
          {sending ? "Sending..." : "Send"}
        </button>
      </form>
    </div>
  );
}
