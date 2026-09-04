import AgentChat from "@/components/ask/AgentChat";

export default function AskPage() {
  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-white">Ask SupplyChainIQ</h1>
        <p className="text-sm text-slate-400">
          Natural-language conversation with the SupplyChainIQ Cortex Agent. Business logic runs entirely in
          Snowflake.
        </p>
      </div>
      <AgentChat />
    </div>
  );
}
