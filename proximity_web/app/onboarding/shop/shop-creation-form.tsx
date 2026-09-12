"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";
import type { DeliveryMode, Shop } from "@/lib/types";

const WEEKDAY_LABELS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

type BusinessHourRow = { weekday: number; opensAt: string; closesAt: string; isClosed: boolean };

const DEFAULT_HOURS: BusinessHourRow[] = WEEKDAY_LABELS.map((_, weekday) => ({
  weekday,
  opensAt: "09:00",
  closesAt: "21:00",
  isClosed: false,
}));

// Posts to POST /v1/shop/shops (routes/shops.ts -> rpc_create_shop,
// migrations/014). Lat/lng are plain number inputs rather than a map
// picker/Places Autocomplete -- SPRINT_PLANNING.md's Sprint 0/1 status is
// explicit that no Google Maps/Geocoding API key exists yet, so a
// geocode-on-submit flow (proximity_app's address_form_screen.dart
// equivalent) isn't buildable against a real, verified API this sprint.
// Swap this for geocoding once that credential exists -- flagged in
// Sprint 2.md's "not yet built" list, not silently left as the permanent
// design.
export function ShopCreationForm() {
  const router = useRouter();
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [addressLine, setAddressLine] = useState("");
  const [city, setCity] = useState("");
  const [pincode, setPincode] = useState("");
  const [lat, setLat] = useState("");
  const [lng, setLng] = useState("");
  const [gstin, setGstin] = useState("");
  const [fssaiLicenseNo, setFssaiLicenseNo] = useState("");
  const [serviceRadiusKm, setServiceRadiusKm] = useState("3");
  const [supportsPickup, setSupportsPickup] = useState(true);
  const [supportsDelivery, setSupportsDelivery] = useState(true);
  const [deliveryMode, setDeliveryMode] = useState<DeliveryMode>("self");
  const [minOrderValuePaise, setMinOrderValuePaise] = useState("0");
  const [hours, setHours] = useState<BusinessHourRow[]>(DEFAULT_HOURS);

  function updateHour(weekday: number, patch: Partial<BusinessHourRow>) {
    setHours((prev) => prev.map((h) => (h.weekday === weekday ? { ...h, ...patch } : h)));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const parsedLat = Number(lat);
    const parsedLng = Number(lng);
    if (Number.isNaN(parsedLat) || Number.isNaN(parsedLng)) {
      setError("Enter valid latitude/longitude for your shop's location");
      return;
    }
    if (!supportsDelivery && deliveryMode !== "self") {
      setError("A shop with delivery turned off must keep delivery mode as \"Self\"");
      return;
    }

    setSubmitting(true);
    try {
      await apiFetchClient<{ data: Shop }>("/v1/shop/shops", {
        method: "POST",
        body: JSON.stringify({
          name,
          description: description || undefined,
          addressLine,
          city,
          pincode,
          location: { lat: parsedLat, lng: parsedLng },
          gstin: gstin || undefined,
          fssaiLicenseNo: fssaiLicenseNo || undefined,
          serviceRadiusKm: Number(serviceRadiusKm) || undefined,
          supportsPickup,
          supportsDelivery,
          deliveryMode,
          minOrderValue: Number(minOrderValuePaise) || 0,
          businessHours: hours,
        }),
      });
      toast.success("Shop submitted for review");
      router.push("/onboarding/pending");
      router.refresh();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not submit your shop");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-6 flex flex-col gap-6">
      <Card>
        <CardContent className="grid gap-4 pt-6 sm:grid-cols-2">
          <div className="flex flex-col gap-2 sm:col-span-2">
            <Label htmlFor="name">Shop name</Label>
            <Input id="name" required value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2 sm:col-span-2">
            <Label htmlFor="description">Description (optional)</Label>
            <Input id="description" value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2 sm:col-span-2">
            <Label htmlFor="addressLine">Address</Label>
            <Input id="addressLine" required value={addressLine} onChange={(e) => setAddressLine(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="city">City</Label>
            <Input id="city" required value={city} onChange={(e) => setCity(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="pincode">Pincode</Label>
            <Input id="pincode" required value={pincode} onChange={(e) => setPincode(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="lat">Latitude</Label>
            <Input id="lat" type="number" step="any" required value={lat} onChange={(e) => setLat(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="lng">Longitude</Label>
            <Input id="lng" type="number" step="any" required value={lng} onChange={(e) => setLng(e.target.value)} />
          </div>
          <p className="text-xs text-muted-foreground sm:col-span-2">
            Look up your shop&apos;s coordinates (e.g. via Google Maps &ldquo;What&apos;s here?&rdquo;) until address
            autocomplete is wired up.
          </p>
          <div className="flex flex-col gap-2">
            <Label htmlFor="gstin">GSTIN (optional)</Label>
            <Input id="gstin" value={gstin} onChange={(e) => setGstin(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="fssai">FSSAI license (optional)</Label>
            <Input id="fssai" value={fssaiLicenseNo} onChange={(e) => setFssaiLicenseNo(e.target.value)} />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="serviceRadius">Service radius (km)</Label>
            <Input
              id="serviceRadius"
              type="number"
              step="0.5"
              min="0.5"
              value={serviceRadiusKm}
              onChange={(e) => setServiceRadiusKm(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="minOrder">Minimum order value (paise)</Label>
            <Input id="minOrder" type="number" min="0" value={minOrderValuePaise} onChange={(e) => setMinOrderValuePaise(e.target.value)} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="flex flex-col gap-4 pt-6">
          <div className="flex flex-wrap gap-6">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={supportsPickup} onChange={(e) => setSupportsPickup(e.target.checked)} />
              Offers pickup
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={supportsDelivery}
                onChange={(e) => {
                  setSupportsDelivery(e.target.checked);
                  if (!e.target.checked) setDeliveryMode("self");
                }}
              />
              Offers delivery
            </label>
          </div>
          {supportsDelivery && (
            <div className="flex flex-col gap-2">
              <Label>Delivery mode</Label>
              <div className="flex flex-col gap-2 text-sm">
                <label className="flex items-center gap-2">
                  <input type="radio" name="deliveryMode" checked={deliveryMode === "self"} onChange={() => setDeliveryMode("self")} />
                  Self-delivered by my own staff (no delivery fee)
                </label>
                <label className="flex items-center gap-2">
                  <input type="radio" name="deliveryMode" checked={deliveryMode === "platform"} onChange={() => setDeliveryMode("platform")} />
                  Proximity riders handle every delivery
                </label>
                <label className="flex items-center gap-2">
                  <input type="radio" name="deliveryMode" checked={deliveryMode === "both"} onChange={() => setDeliveryMode("both")} />
                  Both -- I&apos;ll choose per order
                </label>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="flex flex-col gap-3 pt-6">
          <Label>Business hours</Label>
          {hours.map((h) => (
            <div key={h.weekday} className="grid grid-cols-[6rem_1fr_1fr_auto] items-center gap-3 text-sm">
              <span>{WEEKDAY_LABELS[h.weekday]}</span>
              <Input
                type="time"
                disabled={h.isClosed}
                value={h.opensAt}
                onChange={(e) => updateHour(h.weekday, { opensAt: e.target.value })}
              />
              <Input
                type="time"
                disabled={h.isClosed}
                value={h.closesAt}
                onChange={(e) => updateHour(h.weekday, { closesAt: e.target.value })}
              />
              <label className="flex items-center gap-2 whitespace-nowrap">
                <input type="checkbox" checked={h.isClosed} onChange={(e) => updateHour(h.weekday, { isClosed: e.target.checked })} />
                Closed
              </label>
            </div>
          ))}
        </CardContent>
      </Card>

      {error && <p className="text-sm text-destructive">{error}</p>}
      <Button type="submit" disabled={submitting} size="lg">
        {submitting ? "Submitting..." : "Submit for review"}
      </Button>
    </form>
  );
}
