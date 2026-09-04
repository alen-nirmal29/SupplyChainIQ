export default function LoadingState({ message = "Loading from Snowflake..." }: { message?: string }) {
  return (
    <div className="flex items-center gap-3 rounded-lg border border-control-border bg-control-panel p-6 text-sm text-slate-300">
      <span className="h-4 w-4 animate-spin rounded-full border-2 border-slate-500 border-t-control-accent" />
      {message}
    </div>
  );
}
