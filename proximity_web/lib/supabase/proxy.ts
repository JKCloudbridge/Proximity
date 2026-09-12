import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PUBLIC_PATHS = ["/login", "/signup"];

// Runs on every request (see proxy.ts's matcher, root of the project).
// Refreshes the session cookie and does the fast, edge-cheap half of role
// gating -- the (dashboard)/(admin) layouts re-check server-side as a
// second layer (lib/auth.ts), same two-layer shape as baker_ally_admin's
// proxy.ts/lib/auth.ts split.
//
// Unlike Baker Ally (admin/staff-only web app -- anyone else is simply
// rejected), Proximity's web app has two legitimate authenticated
// audiences sharing one deployable: shopkeepers (/dashboard, /onboarding)
// and admins (/admin). Only /admin/* gets a hard role check here; anything
// else authenticated is allowed through and the page/layout decides what
// to show (a buyer who hasn't created a shop yet still needs to reach
// /onboarding/shop, for instance -- there's no role that "already means"
// shop owner until that flow completes, per SPRINT_PLANNING.md §1.2).
export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => supabaseResponse.cookies.set(name, value, options));
        },
      },
    },
  );

  // Do not run code between createServerClient and getClaims() -- see
  // Supabase's own warning, a mistake here silently logs users out at random.
  const { data } = await supabase.auth.getClaims();
  const role = data?.claims?.app_metadata?.role as string | undefined;
  const isPublicPath = PUBLIC_PATHS.includes(request.nextUrl.pathname);

  if (!data?.claims && !isPublicPath) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  if (data?.claims && request.nextUrl.pathname.startsWith("/admin") && role !== "admin") {
    const url = request.nextUrl.clone();
    url.pathname = "/unauthorized";
    return NextResponse.redirect(url);
  }

  if (data?.claims && isPublicPath) {
    const url = request.nextUrl.clone();
    url.pathname = role === "admin" ? "/admin" : "/dashboard";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
