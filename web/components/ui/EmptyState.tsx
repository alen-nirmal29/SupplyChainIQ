interface EmptyStateProps {
  message: string;
}

export default function EmptyState({ message }: EmptyStateProps) {
  return (
    <div className="surface flex min-h-36 flex-col items-center justify-center border-dashed p-8 text-center text-sm leading-6 text-slate-500">
      <span className="mb-3 flex h-10 w-10 items-center justify-center rounded-full border border-sky-200 bg-sky-50 text-lg text-blue-500" aria-hidden="true">
        &minus;
      </span>
      <span className="max-w-xl">{message}</span>
    </div>
  );
}
