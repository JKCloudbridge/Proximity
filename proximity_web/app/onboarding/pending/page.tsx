import { redirect } from "next/navigation";
import { apiFetch } from "@/lib/api";
import { requireUser } from "@/lib/auth";
import type { Shop } from "@/lib/types";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export default async function OnboardingPendingPage() {
  await requireUser();
  const { data: shops } = await apiFetch<{ data: Shop[] }>("/v1/shop/shops/mine");

  if (shops.length === 0) redirect("/onboarding/shop");
  const shop = shops[0];
  if (shop.status === "approved") redirect("/dashboard");

  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-md text-center">
        <CardHeader>
          <CardTitle>{shop.name}</CardTitle>
          <CardDescription>
            {shop.status === "pending" ? "Waiting on admin review" : "This shop is currently suspended"}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col items-center gap-3">
          <Badge variant={shop.status === "pending" ? "accent" : "destructive"} className="capitalize">
            {shop.status}
          </Badge>
          <p className="text-sm text-muted-foreground">
            {shop.status === "pending"
              ? "An admin needs to approve your shop before it appears to buyers. This page will update once that happens."
              : "Contact Proximity support for details on why this shop was suspended."}
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
