interface ErrorStateProps {
  message: string;
}

/** Renders only a safe, user-facing message. Never pass raw error objects,
 * SQL text, or stack traces into this component. */
export default function ErrorState({ message }: ErrorStateProps) {
  return (
    <div className="rounded-lg border border-red-500/40 bg-red-500/10 p-4 text-sm text-red-200">
      {message}
    </div>
  );
}
