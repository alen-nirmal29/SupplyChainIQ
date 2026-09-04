interface ErrorStateProps {
  message: string;
}

/** Renders only a safe, user-facing message. Never pass raw error objects,
 * SQL text, or stack traces into this component. */
export default function ErrorState({ message }: ErrorStateProps) {
  return (
    <div className="flex items-start gap-3 rounded-xl border border-red-300 bg-red-50/90 p-4 text-sm leading-6 text-red-700 shadow-[0_16px_45px_-32px_rgba(248,113,113,0.35)]" role="alert">
      <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border border-red-400/40 text-xs font-bold" aria-hidden="true">
        !
      </span>
      <span>{message}</span>
    </div>
  );
}
