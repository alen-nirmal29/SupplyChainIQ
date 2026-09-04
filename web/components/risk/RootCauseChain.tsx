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
      <h3 className="section-heading mb-4">Root cause / impact chain</h3>
      <div className="grid grid-cols-1 gap-3 lg:grid-cols-4">
        {stages.map((s, index) => (
          <div key={s.stage} className="relative rounded-xl border border-sky-200/80 bg-white/70 p-4 transition hover:-translate-y-0.5 hover:border-blue-300 hover:bg-blue-50/60 hover:shadow-md">
            <div className="mb-3 flex h-7 w-7 items-center justify-center rounded-lg border border-blue-200 bg-blue-50 text-xs font-semibold text-blue-600">
              {index + 1}
            </div>
            <div className="text-sm font-semibold leading-5 text-[#183052]">
              {s.stage} &mdash; {s.title}
            </div>
            <div className="mt-1.5 text-xs leading-5 text-slate-500">{s.detail}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
