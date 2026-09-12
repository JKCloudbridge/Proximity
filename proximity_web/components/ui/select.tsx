import * as React from "react";

import { cn } from "@/lib/utils";

// Same hand-written-to-match-the-shadcn-shape convention as the rest of
// components/ui (see button.tsx's header comment) -- a plain native
// <select>, not Radix's Select, which is enough for this sprint's flat
// category/sub-category/stock-status dropdowns.
export function Select({ className, ...props }: React.ComponentProps<"select">) {
  return (
    <select
      className={cn(
        "flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm shadow-xs transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...props}
    />
  );
}
