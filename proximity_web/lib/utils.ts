import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

// Standard shadcn/ui `cn` helper -- merges conditional class lists and
// resolves conflicting Tailwind utility classes (e.g. two different
// `px-*` values) in favor of the later one. Hand-written rather than
// pulled in via the shadcn CLI (see components/ui/*'s header comment for
// why), but this is the same well-known one-liner every shadcn project has.
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
