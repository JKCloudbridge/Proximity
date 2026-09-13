"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import type { PlatformSetting } from "@/lib/types";

function findSetting<K extends PlatformSetting["key"]>(settings: PlatformSetting[], key: K) {
  return settings.find((s) => s.key === key) as Extract<PlatformSetting, { key: K }> | undefined;
}

// Three small forms, one per known platform_settings key -- deliberately not
// a single generic "edit this JSON blob" editor: routes/admin.ts's own
// platformSettingSchema validates each key's `value` shape specifically
// (migrations/012's own seed-row comment is the only place these shapes
// were ever documented before this sprint), so the UI mirrors that same
// per-key structure rather than exposing raw JSON an admin could typo.
export function SettingsClient({ initialSettings }: { initialSettings: PlatformSetting[] }) {
  const [settings, setSettings] = useState(initialSettings);
  const deliveryFee = findSetting(settings, "platform_rider_delivery_fee");
  const slotWindow = findSetting(settings, "slot_window");
  const commission = findSetting(settings, "default_shop_commission_pct");

  const [feeRupees, setFeeRupees] = useState(String((deliveryFee?.value.amount_paise ?? 0) / 100));
  const [slotStart, setSlotStart] = useState(slotWindow?.value.start ?? "06:00");
  const [slotEnd, setSlotEnd] = useState(slotWindow?.value.end ?? "24:00");
  const [slotMinutes, setSlotMinutes] = useState(String(slotWindow?.value.slot_minutes ?? 120));
  const [defaultCommission, setDefaultCommission] = useState(String(commission?.value.value ?? 10));
  const [saving, setSaving] = useState<string | null>(null);

  async function save(key: PlatformSetting["key"], value: unknown) {
    setSaving(key);
    try {
      const { data } = await apiFetchClient<{ data: PlatformSetting }>("/v1/admin/platform-settings", {
        method: "PATCH",
        body: JSON.stringify({ key, value }),
      });
      setSettings((prev) => [...prev.filter((s) => s.key !== key), data]);
      toast.success("Saved -- takes effect on the next request that reads it");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not save");
    } finally {
      setSaving(null);
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Platform rider delivery fee</CardTitle>
          <CardDescription>
            Charged only when a Proximity rider fulfills the delivery (§1.3 -- self-fulfilled orders never carry this
            fee). Reflected on the very next checkout that reads it -- there is no cache to invalidate.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Label htmlFor="fee">Fee (₹)</Label>
          <Input id="fee" type="number" min="0" step="0.01" value={feeRupees} onChange={(e) => setFeeRupees(e.target.value)} />
        </CardContent>
        <CardFooter>
          <Button
            disabled={saving === "platform_rider_delivery_fee"}
            onClick={() => save("platform_rider_delivery_fee", { amount_paise: Math.round(Number(feeRupees) * 100) })}
          >
            Save
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Fulfillment slot window</CardTitle>
          <CardDescription>The platform-wide default window and granularity (§1.6), clipped per shop by their own business hours.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-3">
          <div>
            <Label htmlFor="start">Start (HH:mm)</Label>
            <Input id="start" value={slotStart} onChange={(e) => setSlotStart(e.target.value)} placeholder="06:00" />
          </div>
          <div>
            <Label htmlFor="end">End (HH:mm)</Label>
            <Input id="end" value={slotEnd} onChange={(e) => setSlotEnd(e.target.value)} placeholder="24:00" />
          </div>
          <div>
            <Label htmlFor="minutes">Slot length (minutes)</Label>
            <Input id="minutes" type="number" min="1" value={slotMinutes} onChange={(e) => setSlotMinutes(e.target.value)} />
          </div>
        </CardContent>
        <CardFooter>
          <Button
            disabled={saving === "slot_window"}
            onClick={() => save("slot_window", { start: slotStart, end: slotEnd, slot_minutes: Number(slotMinutes) })}
          >
            Save
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Default shop commission</CardTitle>
          <CardDescription>
            Applied to a shop at creation time; use a shop&rsquo;s own row in Shop approvals to override it for one specific
            shop afterwards.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Label htmlFor="commission">Commission (%)</Label>
          <Input
            id="commission"
            type="number"
            min="0"
            max="100"
            step="0.01"
            value={defaultCommission}
            onChange={(e) => setDefaultCommission(e.target.value)}
          />
        </CardContent>
        <CardFooter>
          <Button
            disabled={saving === "default_shop_commission_pct"}
            onClick={() => save("default_shop_commission_pct", { value: Number(defaultCommission) })}
          >
            Save
          </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
