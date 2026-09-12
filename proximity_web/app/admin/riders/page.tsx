import { apiFetch } from "@/lib/api";
import type { Rider } from "@/lib/types";
import { RidersClient } from "./riders-client";

export default async function AdminRidersPage() {
  const { data: riders } = await apiFetch<{ data: Rider[] }>("/v1/admin/riders");
  return <RidersClient initialRiders={riders} />;
}
