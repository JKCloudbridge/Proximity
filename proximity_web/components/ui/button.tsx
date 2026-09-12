import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";

import { cn } from "@/lib/utils";

// Hand-written to match the shape `npx shadcn add button` generates
// (cva variants, Radix-less plain <button>) -- this whole components/ui
// folder is written by hand rather than fetched via the shadcn CLI. That
// CLI needs a live registry round-trip on top of the npm install this
// sprint's proximity_web scaffold already hit real ENOTEMPTY/EPERM
// file-lock flakiness on (OneDrive syncing node_modules mid-write) -- not
// worth a second flaky network dependency for component *source* this
// small. If a redesign wants Radix-backed primitives (Dialog, Sheet, etc.)
// later, running the real CLI then is still an option; this isn't a
// permanent decision, just this sprint's pragmatic one.
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        outline: "border border-input bg-background hover:bg-secondary",
        ghost: "hover:bg-secondary hover:text-secondary-foreground",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
      },
      size: {
        default: "h-9 px-4 py-2",
        sm: "h-8 rounded-md px-3 text-xs",
        lg: "h-10 rounded-md px-6",
      },
    },
    defaultVariants: { variant: "default", size: "default" },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {}

export function Button({ className, variant, size, ...props }: ButtonProps) {
  return <button className={cn(buttonVariants({ variant, size, className }))} {...props} />;
}
