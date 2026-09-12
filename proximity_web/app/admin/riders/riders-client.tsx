"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { Rider } from "@/lib/types";

const TABS = [
  { value: "false", label: "Pending" },
  { value: "true", label: "Verified" },
  { value: "", label: "All" },
] as const;

export function RidersClient({ initialRiders }: { initialRiders: Rider[] }) {
  const [tab, setTab] = useState<(typeof TABS)[number]["value"]>("false");
  const [riders, setRiders] = useState(initialRiders);
  const [loading, setLoading] = useState(false);
  const [actingOn, setActingOn] = useState<string | null>(null);

  async function loadTab(next: (typeof TABS)[number]["value"]) {
    setTab(next);
    setLoading(true);
    try {
      const query = next === "" ? "" : `?verified=${next}`;
      const { data } = await apiFetchClient<{ data: Rider[] }>(`/v1/admin/riders${query}`);
      setRiders(data);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not load riders");
    } finally {
      setLoading(false);
    }
  }

  async function act(riderId: string, action: "approve" | "revoke") {
    setActingOn(riderId);
    try {
      await apiFetchClient(`/v1/admin/riders/${riderId}/${action}`, { method: "POST" });
      toast.success(action === "approve" ? "Rider approved" : "Approval revoked");
      await loadTab(tab);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Action failed");
    } finally {
      setActingOn(null);
    }
  }

  return (
    <div>
      <div className="mb-4 flex gap-1 border-b">
        {TABS.map((t) => (
          <button
            key={t.value}
            onClick={() => loadTab(t.value)}
            className={cn(
              "border-b-2 border-transparent px-3 py-2 text-sm font-medium text-muted-foreground",
              tab === t.value && "border-primary text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : riders.length === 0 ? (
        <p className="text-sm text-muted-foreground">No riders here.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted text-left text-muted-foreground">
              <tr>
                <th className="px-4 py-2 font-medium">Name</th>
                <th className="px-4 py-2 font-medium">Phone</th>
                <th className="px-4 py-2 font-medium">Vehicle</th>
                <th className="px-4 py-2 font-medium">KYC document</th>
                <th className="px-4 py-2 font-medium">Status</th>
                <th className="px-4 py-2 font-medium" />
              </tr>
            </thead>
            <tbody>
              {riders.map((rider) => (
                <tr key={rider.id} className="border-t">
                  <td className="px-4 py-2 font-medium">{rider.fullName}</td>
                  <td className="px-4 py-2">{rider.phone}</td>
                  <td className="px-4 py-2 capitalize">{rider.vehicleType?.replace("_", " ") ?? "—"}</td>
                  <td className="px-4 py-2">
                    {rider.kycDocumentUrl ? (
                      <Badge variant="secondary">Uploaded</Badge>
                    ) : (
                      <Badge variant="destructive">Missing</Badge>
                    )}
                  </td>
                  <td className="px-4 py-2">
                    <Badge variant={rider.isVerified ? "default" : "accent"}>{rider.isVerified ? "Verified" : "Pending"}</Badge>
                  </td>
                  <td className="px-4 py-2 text-right">
                    {rider.isVerified ? (
                      <Button size="sm" variant="destructive" disabled={actingOn === rider.id} onClick={() => act(rider.id, "revoke")}>
                        Revoke
                      </Button>
                    ) : (
                      <Button size="sm" disabled={actingOn === rider.id} onClick={() => act(rider.id, "approve")}>
                        Approve
                      </Button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="mt-3 text-xs text-muted-foreground">
        &ldquo;Uploaded&rdquo; means a document path exists in the private rider-documents bucket -- viewing it inline isn&apos;t built
        yet (Sprint 2.md).
      </p>
    </div>
  );
}
