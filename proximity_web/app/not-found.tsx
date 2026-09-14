import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";

// Sprint 13 -- same gap error.tsx's own header documents: no boundary of any
// kind existed anywhere in this app before this sprint. This one covers an
// unmatched route (a mistyped /admin/shpos, a stale bookmark to a page that
// moved) -- Next.js renders this automatically for any URL under this app
// that doesn't match a route, same "one root file, every nested route
// inherits it" mechanism error.tsx uses. Can stay a Server Component (no
// client-only APIs needed here, unlike error.tsx's required `reset()`).
export default function NotFound() {
  return (
    <div className="flex min-h-screen items-center justify-center p-6">
      <div className="max-w-sm text-center">
        <h1 className="font-[family-name:var(--font-display)] text-2xl font-semibold">Page not found</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          That page doesn&rsquo;t exist, or it moved. Double-check the link, or head back to the dashboard.
        </p>
        <Link href="/dashboard" className={buttonVariants({ className: "mt-6" })}>
          Go to dashboard
        </Link>
      </div>
    </div>
  );
}
