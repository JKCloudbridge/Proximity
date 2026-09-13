import { apiFetch } from "@/lib/api";
import type { PlatformSetting } from "@/lib/types";
import { SettingsClient } from "./settings-client";

// Sprint 12 -- §8.6's "platform_settings editor UI (delivery fee/slot
// window)," §11's own exit criteria: "admin can change the platform
// delivery fee and see it reflected on the next new order." Server-fetches
// every row on load -- there are only ever three keys (migrations/012's
// seed), so no pagination/filtering is needed the way the shop/rider queues
// have.
export default async function AdminSettingsPage() {
  const { data: settings } = await apiFetch<{ data: PlatformSetting[] }>("/v1/admin/platform-settings");
  return <SettingsClient initialSettings={settings} />;
}
