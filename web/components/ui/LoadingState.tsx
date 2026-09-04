export default function LoadingState({ message = "Loading from Snowflake..." }: { message?: string }) {
  return (
    <div className="surface relative min-h-40 overflow-hidden p-5" role="status">
      <div className="loading-sheen pointer-events-none absolute inset-y-0 w-1/3 bg-gradient-to-r from-transparent via-blue-100/60 to-transparent" />
      <div className="mb-5 flex items-center gap-3 text-sm text-slate-500">
        <span className="h-5 w-5 animate-spin rounded-full border-2 border-blue-100 border-r-blue-500 border-t-blue-500 shadow-[0_0_12px_rgba(59,130,246,0.18)]" />
        <span>{message}</span>
      </div>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3" aria-hidden="true">
        {[0, 1, 2].map((item) => (
          <div key={item} className="rounded-xl border border-sky-100 bg-sky-50/50 p-4">
            <div className="h-2.5 w-24 animate-pulse rounded-full bg-sky-200/70" />
            <div className="mt-4 h-6 w-16 animate-pulse rounded-md bg-blue-100/80" />
          </div>
        ))}
      </div>
    </div>
  );
}
