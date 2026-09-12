// Mirrors proximity_backend's response shapes (routes/auth.ts,
// routes/shops.ts, routes/riders.ts) -- kept in step with schema.ts the
// same "grows with what's actually built" discipline as the backend's own
// schema.ts. `numeric` Postgres columns come back as strings through
// Drizzle by default (avoids float-precision surprises on money/percentage
// values) -- serviceRadiusKm/platformCommissionPct reflect that here rather
// than being typed `number` and quietly wrong.

export type Role = "buyer" | "shop_owner" | "rider" | "admin";

export type AppUser = {
  id: string;
  role: Role;
  fullName: string | null;
  phone: string | null;
  email: string | null;
  avatarUrl: string | null;
};

export type MeResponse = { data: { user: AppUser; role: Role } };

export type DeliveryMode = "self" | "platform" | "both";
export type ShopStatus = "pending" | "approved" | "suspended";

export type Shop = {
  id: string;
  ownerId: string;
  name: string;
  description: string | null;
  logoUrl: string | null;
  coverImageUrl: string | null;
  gstin: string | null;
  fssaiLicenseNo: string | null;
  addressLine: string;
  city: string;
  pincode: string;
  serviceRadiusKm: string;
  supportsPickup: boolean;
  supportsDelivery: boolean;
  deliveryMode: DeliveryMode;
  minOrderValue: number;
  status: ShopStatus;
  platformCommissionPct: string;
  createdAt: string;
  updatedAt: string;
};

export type BusinessHour = {
  id: string;
  shopId: string;
  weekday: number; // 0=Sunday..6=Saturday, migrations/008
  opensAt: string | null; // "HH:MM:SS"
  closesAt: string | null;
  isClosed: boolean;
};

export type VehicleType = "bike" | "scooter" | "bicycle" | "on_foot";
export type RiderStatus = "offline" | "available" | "on_delivery";

export type Rider = {
  id: string;
  userId: string;
  fullName: string;
  phone: string;
  vehicleType: VehicleType | null;
  vehicleNumber: string | null;
  kycDocumentUrl: string | null; // storage path, not a resolvable URL -- see routes/riders.ts's comment
  status: RiderStatus;
  isVerified: boolean;
  createdAt: string;
};
