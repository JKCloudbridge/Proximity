import { redirect } from "next/navigation";
import { apiFetch } from "@/lib/api";
import { requireUser } from "@/lib/auth";
import type { Shop } from "@/lib/types";
import { ShopCreationForm } from "./shop-creation-form";

// §8.1: signup -> shop creation form -> delivery-mode selection -> pending
// status -> admin approval. Any authenticated user reaches this page
// (there's no "shop_owner-only" gate to fail here -- see routes/shops.ts's
// header comment for why); if they already have a shop, skip straight to
// wherever that shop's status says to go instead of showing the form again.
export default async function ShopOnboardingPage() {
  await requireUser();
  const { data: shops } = await apiFetch<{ data: Shop[] }>("/v1/shop/shops/mine");

  if (shops.length > 0) {
    redirect(shops[0].status === "pending" ? "/onboarding/pending" : "/dashboard");
  }

  return (
    <div className="mx-auto max-w-2xl p-6">
      <h1 className="text-2xl font-semibold">Tell us about your shop</h1>
      <p className="mt-1 text-muted-foreground">
        An admin reviews every new shop before it goes live to buyers.
      </p>
      <ShopCreationForm />
    </div>
  );
}
