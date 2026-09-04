import AgentChat from "@/components/ask/AgentChat";

export default function AskPage() {
  return (
    <div className="page-shell">
      <div className="page-header">
        <div>
        <h1 className="page-title">Ask SupplyChainIQ</h1>
        <p className="page-description">
          Natural-language conversation with the SupplyChainIQ Cortex Agent. Business logic runs entirely in
          Snowflake.
        </p>
        </div>
      </div>
      <AgentChat />
    </div>
  );
}
