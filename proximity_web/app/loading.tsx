// Sprint 13 -- the third of the three root boundary files this app never
// had (see error.tsx's header for the full "why this was missing" account).
// Next.js shows this automatically while a route segment's own async Server
// Component work (every page.tsx's server-side `apiFetch`) is still in
// flight -- without it, that wait was a blank white flash, not a branded
// loading state, on every first paint of every dashboard/admin page.
export default function Loading() {
  return (
    <div className="flex min-h-screen items-center justify-center">
      <div
        className="h-8 w-8 animate-spin rounded-full border-2 border-muted-foreground/30 border-t-primary"
        role="status"
        aria-label="Loading"
      />
    </div>
  );
}
