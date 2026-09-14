"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";

// Sprint 13 -- caught by this sprint's own "empty/error states on every
// list screen" audit, widened once it became clear the gap wasn't a list
// screen at all: NO route in this app (dashboard/*, admin/*, onboarding/*,
// login, signup) had any error boundary anywhere, and every one of their
// page.tsx files does an unguarded server-side `apiFetch` (see e.g.
// admin/shops/page.tsx) -- a thrown fetch (the backend unreachable, which is
// this project's actual current state: no Supabase project, no deployed
// Edge Function) would have rendered Next.js's own generic, unstyled crash
// page instead of anything belonging to this design system. One root-level
// `error.tsx` catches every uncaught render/fetch error from any page or
// nested layout below it (Next.js App Router's own error-boundary
// convention -- checked directly against the actually-installed
// next@16.3.5 source, `error-boundary.d.ts`, rather than assumed from
// training-data-era Next.js docs: this version's error component receives
// `{ error: unknown; reset: () => void; retry: () => void }`, NOT the
// `Error & { digest?: string }` shape older Next.js versions typed it as).
// A more specific `error.tsx` under app/dashboard or app/admin is a cheap
// future addition (e.g. to keep the shopkeeper and admin chrome around the
// error) but isn't required for the exit criteria this sprint actually
// names ("no unhandled empty states") -- this root one already means no
// page in this app can crash to an unstyled screen.
//
// Must be a Client Component ("use client") -- Next.js's own requirement
// for any error.tsx, since it has to run in the browser to catch a render
// error and offer a `reset()` retry.
export default function GlobalErrorBoundary({ error, reset }: { error: unknown; reset: () => void }) {
  const message = error instanceof Error ? error.message : "Something went wrong.";
  const router = useRouter();

  useEffect(() => {
    // No Sentry wiring exists yet at this layer (this sprint's own backend
    // error-tracking decision is Edge-Function-side, not this Next.js app --
    // see Sprint 13.md) -- console.error is the honest, real behavior today,
    // not a stand-in for something already wired.
    console.error("proximity_web render error:", error);
  }, [error]);

  return (
    <div className="flex min-h-screen items-center justify-center p-6">
      <Card className="max-w-md">
        <CardHeader>
          <CardTitle className="font-[family-name:var(--font-display)] text-lg">Something went wrong</CardTitle>
          <CardDescription>{message}</CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          This is usually the backend being unreachable rather than anything on your end. Try again, and if it keeps
          happening, check that the Edge Function and database are actually up.
        </CardContent>
        <CardFooter className="gap-2">
          <Button onClick={() => reset()}>Try again</Button>
          <Button variant="outline" onClick={() => router.push("/")}>
            Go home
          </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
