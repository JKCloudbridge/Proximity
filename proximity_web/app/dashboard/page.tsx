import { redirect } from "next/navigation";
import { requireShop } from "@/lib/auth";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

const STATUS_VARIANT = {
  pending: "accent",
  approved: "default",
  suspended: "destructive",
} as const;

// Sprint 2's dashboard is a status overview only -- catalog/orders/sales/
// team (§8.2-§8.4) land in their own sprints (3, 12). A shop still in
// 'pending' or 'suspended' bounces to /onboarding/pending instead of
// showing this overview, so nothing here has to handle "not approved yet"
// as a display state.
export default async function DashboardPage() {
  const { shop } = await requireShop();
  if (shop.status !== "approved") redirect("/onboarding/pending");

  return (
    <div className="mx-auto max-w-3xl">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="text-xl">{shop.name}</CardTitle>
            <Badge variant={STATUS_VARIANT[shop.status]} className="capitalize">
              {shop.status}
            </Badge>
          </div>
          <CardDescription>
            {shop.addressLine}, {shop.city} {shop.pincode}
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 text-sm sm:grid-cols-2">
          <div>
            <div className="text-muted-foreground">Delivery mode</div>
            <div className="capitalize">{shop.deliveryMode}</div>
          </div>
          <div>
            <div className="text-muted-foreground">Fulfillment</div>
            <div>
              {[shop.supportsPickup && "Pickup", shop.supportsDelivery && "Delivery"].filter(Boolean).join(" · ") || "None"}
            </div>
          </div>
          <div>
            <div className="text-muted-foreground">Service radius</div>
            <div>{shop.serviceRadiusKm} km</div>
          </div>
          <div>
            <div className="text-muted-foreground">Platform commission</div>
            <div>{shop.platformCommissionPct}%</div>
          </div>
        </CardContent>
      </Card>
      <p className="mt-6 text-sm text-muted-foreground">
        Catalog management, orders, and sales reporting arrive in a later update.
      </p>
    </div>
  );
}
