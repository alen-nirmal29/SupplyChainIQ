import { formatPercent } from "@/lib/format";
import type { ConfirmedRisk } from "@/types/risk";

interface RootCauseChainProps {
  risk: ConfirmedRisk;
}

/** Presentation-only chain composed from governed risk fields -- no
 * business state is derived here, everything comes from the risk row. */
export default function RootCauseChain({ risk }: RootCauseChainProps) {
  const stages = [
    {
      stage: "Supplier",
      title: risk.SUPPLIER_NAME || risk.SUPPLIER_ID,
      detail:
        risk.SUPPLIER_OTD_PERCENT != null
          ? `Historical supplier OTD: ${formatPercent(risk.SUPPLIER_OTD_PERCENT)}`
          : "No governed historical supplier OTD is available for this risk.",
    },
    {
      stage: "Shipment",
      title: risk.DELAYED_SHIPMENT_ID ? "Inbound shipment delayed" : "No delayed inbound shipment attributed",
      detail: risk.DELAYED_SHIPMENT_ID
        ? `${risk.DELAYED_SHIPMENT_ID} is ${risk.DELAY_DAYS} day(s) behind its promised date.`
        : "Risk remains based on governed inventory and open customer-order demand.",
    },
    {
      stage: "Inventory constraint",
      title: `${risk.PART_ID} at ${risk.PLANT_NAME}`,
      detail: `Governed shortage: ${risk.SHORTAGE_QUANTITY} units after safety stock.`,
    },
    {
      stage: "Customer impact",
      title: "Open customer demand at risk",
      detail: `${risk.AFFECTED_ORDER_LINES} order line(s); first due ${risk.FIRST_CUSTOMER_DUE_DATE ?? "\u2014"}; revenue exposure is INR ${risk.REVENUE_EXPOSURE ?? "\u2014"}.`,
    },
  ];

  return (
    <div>
      <h3 className="mb-3 text-sm font-semibold text-white">Root cause / impact chain</h3>
      <div className="space-y-2">
        {stages.map((s) => (
          <div key={s.stage} className="rounded-lg border border-control-border bg-control-panel p-3">
            <div className="text-sm font-medium text-white">
              {s.stage} &mdash; {s.title}
            </div>
            <div className="text-xs text-slate-400">{s.detail}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
