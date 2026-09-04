interface EmptyStateProps {
  message: string;
}

export default function EmptyState({ message }: EmptyStateProps) {
  return (
    <div className="rounded-lg border border-dashed border-control-border bg-control-panel/50 p-8 text-center text-sm text-slate-400">
      {message}
    </div>
  );
}
