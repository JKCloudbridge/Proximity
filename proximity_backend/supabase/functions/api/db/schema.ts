import { boolean, index, integer, jsonb, numeric, pgTable, smallint, text, time, timestamp, unique, uuid } from "npm:drizzle-orm/pg-core";

// Mirrors migrations/001-015 -- see those files for constraints/comments
// this schema doesn't repeat (RLS policies, CHECK constraints, extension
// setup). Sprint 1 subset was users, addresses, categories. Sprint 2 adds
// shops, shop_team_members, shop_business_hours, riders, platform_settings.
// shop_media/shop_sub_categories/shop_blackout_dates exist as migrations
// but have no route yet (Sprint 2.md), so they're intentionally not added
// here either -- same "schema.ts grows in step with what a route actually
// touches" discipline as everything else in this file. products/variants
// land in Sprint 3. Keep this file growing in step with migrations/, never
// ahead of it.
//
// Note: `location GEOGRAPHY(Point,4326)` on `addresses` (and now `shops`,
// `riders.current_location`) has no clean Drizzle pg-core column type -- a
// raw SQL column here isn't possible without drizzle-orm's `customType`,
// which this project still doesn't need (shop creation writes `location` in
// one INSERT inside rpc_create_shop's raw SQL, not through Drizzle -- see
// migrations/014 -- and nothing yet reads it back out through a route, so
// there's still no third caller motivating building the customType
// abstraction addresses.ts's comment flagged as the trigger for doing so).

export const users = pgTable("users", {
  id: uuid("id").primaryKey(),
  role: text("role").notNull().default("buyer"),
  fullName: text("full_name"),
  phone: text("phone"),
  email: text("email"),
  avatarUrl: text("avatar_url"),
  fcmToken: text("fcm_token"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const addresses = pgTable(
  "addresses",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    label: text("label"),
    line1: text("line1").notNull(),
    line2: text("line2"),
    city: text("city").notNull(),
    state: text("state").notNull(),
    pincode: text("pincode").notNull(),
    // location GEOGRAPHY(Point,4326) intentionally omitted -- see file header.
    isDefault: boolean("is_default").notNull().default(false),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("idx_addresses_user_id").on(table.userId)],
);

export const categories = pgTable("categories", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull().unique(),
  icon: text("icon"),
  imageUrl: text("image_url"),
  sortOrder: integer("sort_order").notNull().default(0),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 2 (migrations/006). `location` intentionally omitted -- see file
// header. Written/read as raw SQL (rpc_create_shop, migrations/014) rather
// than through this Drizzle definition for the one column that needs it.
export const shops = pgTable("shops", {
  id: uuid("id").primaryKey().defaultRandom(),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => users.id),
  name: text("name").notNull(),
  description: text("description"),
  logoUrl: text("logo_url"),
  coverImageUrl: text("cover_image_url"),
  gstin: text("gstin"),
  fssaiLicenseNo: text("fssai_license_no"),
  addressLine: text("address_line").notNull(),
  city: text("city").notNull(),
  pincode: text("pincode").notNull(),
  serviceRadiusKm: numeric("service_radius_km", { precision: 4, scale: 1 }).notNull().default("3.0"),
  supportsPickup: boolean("supports_pickup").notNull().default(true),
  supportsDelivery: boolean("supports_delivery").notNull().default(true),
  deliveryMode: text("delivery_mode").notNull().default("self"),
  minOrderValue: integer("min_order_value").notNull().default(0),
  status: text("status").notNull().default("pending"),
  platformCommissionPct: numeric("platform_commission_pct", { precision: 4, scale: 2 }).notNull().default("10.00"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 2 (migrations/007) -- §1.2's shop-scoped fine-grained membership,
// not a global role. See rpc_create_shop (014) for how the owner row gets
// its first insert (never a bare Drizzle insert, per §4.4).
export const shopTeamMembers = pgTable(
  "shop_team_members",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    shopId: uuid("shop_id")
      .notNull()
      .references(() => shops.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    memberRole: text("member_role").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [unique("shop_team_members_shop_id_user_id_key").on(table.shopId, table.userId)],
);

// Sprint 2 (migrations/008). weekday follows Postgres's own EXTRACT(DOW)
// convention (0=Sunday..6=Saturday) -- see that migration's comment.
export const shopBusinessHours = pgTable(
  "shop_business_hours",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    shopId: uuid("shop_id")
      .notNull()
      .references(() => shops.id, { onDelete: "cascade" }),
    weekday: smallint("weekday").notNull(),
    opensAt: time("opens_at"),
    closesAt: time("closes_at"),
    isClosed: boolean("is_closed").notNull().default(false),
  },
  (table) => [unique("shop_business_hours_shop_id_weekday_key").on(table.shopId, table.weekday)],
);

// Sprint 2 (migrations/011). `currentLocation` (GEOGRAPHY) omitted -- same
// reasoning as `shops.location`; nothing reads/writes it via this schema
// yet (rider live-location pings land with the rider app touchpoint,
// Sprint 9, §8.5).
export const riders = pgTable("riders", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .unique()
    .references(() => users.id, { onDelete: "cascade" }),
  fullName: text("full_name").notNull(),
  phone: text("phone").notNull(),
  vehicleType: text("vehicle_type"),
  vehicleNumber: text("vehicle_number"),
  kycDocumentUrl: text("kyc_document_url"),
  status: text("status").notNull().default("offline"),
  isVerified: boolean("is_verified").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 2 (migrations/012). `value` stays untyped `unknown` at this layer
// (drizzle's `jsonb()` with no `.$type<>()`) -- each key's shape is
// documented in the migration's seed-row comment, not re-declared here; the
// routes that read specific keys narrow it with zod at the boundary instead
// of forcing one Drizzle column type to fit three different value shapes.
export const platformSettings = pgTable("platform_settings", {
  key: text("key").primaryKey(),
  value: jsonb("value").notNull(),
  updatedBy: uuid("updated_by").references(() => users.id),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});
