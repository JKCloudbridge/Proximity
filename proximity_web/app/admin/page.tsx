import { redirect } from "next/navigation";

// No standalone admin landing page this sprint -- §8.6's exit criteria is
// just the two approval queues, so "/admin" simply lands on the first one
// rather than showing an empty dashboard shell.
export default function AdminIndexPage() {
  redirect("/admin/shops");
}
