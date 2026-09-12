import { boolean, date, index, integer, jsonb, numeric, pgTable, smallint, text, time, timestamp, unique, uuid } from "npm:drizzle-orm/pg-core";

// Mirrors migrations/001-020 -- see those files for constraints/comments
// this schema doesn't repeat (RLS policies, CHECK constraints, extension
// setup). Sprint 1 subset was users, addresses, categories. Sprint 2 adds
// shops, shop_team_members, shop_business_hours, riders, platform_settings.
// Sprint 3 adds shop_sub_categories, products, product_variants,
// product_images -- shop_media/shop_blackout_dates still have no route, so
// they're intentionally still not added here -- same "schema.ts grows in
// step with what a route actually touches" discipline as everything else in
// this file. Keep this file growing in step with migrations/, never ahead
// of it.
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

// Sprint 3 (migrations/010). Table existed since Sprint 2; this is its
// first route (routes/catalog.ts).
export const shopSubCategories = pgTable(
  "shop_sub_categories",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    shopId: uuid("shop_id")
      .notNull()
      .references(() => shops.id, { onDelete: "cascade" }),
    categoryId: uuid("category_id")
      .notNull()
      .references(() => categories.id),
    name: text("name").notNull(),
    iconUrl: text("icon_url"),
    sortOrder: integer("sort_order").notNull().default(0),
    isActive: boolean("is_active").notNull().default(true),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [unique("shop_sub_categories_shop_id_category_id_name_key").on(table.shopId, table.categoryId, table.name)],
);

// Sprint 3 (migrations/017). `searchVector` intentionally omitted -- same
// "no clean Drizzle pg-core column type, no route reads/writes it yet"
// reasoning as `shops.location` (see this file's header comment); it's a
// STORED generated column maintained entirely by Postgres, never set from
// application code.
export const products = pgTable("products", {
  id: uuid("id").primaryKey().defaultRandom(),
  shopId: uuid("shop_id")
    .notNull()
    .references(() => shops.id, { onDelete: "cascade" }),
  categoryId: uuid("category_id")
    .notNull()
    .references(() => categories.id),
  subCategoryId: uuid("sub_category_id").references(() => shopSubCategories.id),
  name: text("name").notNull(),
  description: text("description"),
  isVeg: boolean("is_veg"),
  infoMessage: text("info_message"),
  isActive: boolean("is_active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 3 (migrations/018). price/mrp are paise integers (§1.7's
// paise-integer-money convention); numeric columns (unitValue) come back as
// strings through Drizzle by default, same note proximity_web's types.ts
// makes for serviceRadiusKm/platformCommissionPct.
export const productVariants = pgTable(
  "product_variants",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    productId: uuid("product_id")
      .notNull()
      .references(() => products.id, { onDelete: "cascade" }),
    unitValue: numeric("unit_value", { precision: 10, scale: 2 }).notNull(),
    unitLabel: text("unit_label").notNull(),
    sku: text("sku"),
    price: integer("price").notNull(),
    mrp: integer("mrp"),
    stockQty: integer("stock_qty").notNull().default(0),
    stockStatus: text("stock_status").notNull().default("in_stock"),
    isActive: boolean("is_active").notNull().default(true),
    sortOrder: integer("sort_order").notNull().default(0),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    unique("product_variants_product_id_unit_value_unit_label_key").on(table.productId, table.unitValue, table.unitLabel),
  ],
);

// Sprint 3 (migrations/019).
export const productImages = pgTable("product_images", {
  id: uuid("id").primaryKey().defaultRandom(),
  productId: uuid("product_id")
    .notNull()
    .references(() => products.id, { onDelete: "cascade" }),
  imageUrl: text("image_url").notNull(),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 5 (migrations/021) -- see that file's header for why this is a
// fresh design against §4.10's prose rather than a transcription. Scoped to
// the product, not one product_variant -- routes/wishlist.ts's own header
// repeats the reasoning.
export const wishlists = pgTable(
  "wishlists",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    productId: uuid("product_id")
      .notNull()
      .references(() => products.id, { onDelete: "cascade" }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [unique("wishlists_user_id_product_id_key").on(table.userId, table.productId)],
);

// Sprint 6 (migrations/022) -- see that file's header for where this
// table's DDL actually came from (Baker Ally's recovered v1 original, not a
// fresh prose-only design like wishlists above). One cart per user; created
// lazily by rpc_add_to_cart (024), never at signup.
export const carts = pgTable("carts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .unique()
    .references(() => users.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 6 (migrations/023) -- literal DDL from SPRINT_PLANNING.md §1.5, no
// shop lock (that section's own point: the multi-shop cart's shop grouping
// is client-side presentation, not a data-model constraint). Rows are
// written through rpc_add_to_cart (024) for the upsert-on-add path; plain
// Drizzle update/delete for the cart screen's quantity stepper and
// remove/remove-all-from-shop actions (routes/cart.ts), same "not every
// multi-statement write needs SECURITY DEFINER" judgment call as shops.ts's
// business-hours PUT.
export const cartItems = pgTable(
  "cart_items",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    cartId: uuid("cart_id")
      .notNull()
      .references(() => carts.id, { onDelete: "cascade" }),
    variantId: uuid("variant_id")
      .notNull()
      .references(() => productVariants.id, { onDelete: "cascade" }),
    quantity: integer("quantity").notNull().default(1),
    addedAt: timestamp("added_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [unique("cart_items_cart_id_variant_id_key").on(table.cartId, table.variantId)],
);

// Sprint 2 (migrations/013), added to this file in Sprint 7 -- the table has
// existed since Sprint 2 but deliberately stayed out of here until a route
// actually touched it (that file's own header said the slot generator would
// be the one to, "Sprint 7, alongside checkout"). This is that route:
// routes/checkout.ts's fulfillment-slots handler. `date` is a DATE column,
// which Drizzle round-trips as a "YYYY-MM-DD" string rather than a JS Date
// -- which is what the slot generator wants anyway, since every date in
// that path is an IST calendar date, not an instant.
export const shopBlackoutDates = pgTable(
  "shop_blackout_dates",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    shopId: uuid("shop_id")
      .notNull()
      .references(() => shops.id, { onDelete: "cascade" }),
    date: date("date").notNull(),
    reason: text("reason"),
  },
  (table) => [unique("shop_blackout_dates_shop_id_date_key").on(table.shopId, table.date)],
);

// Sprint 7 (migrations/026) -- admin-authored, platform-wide discount
// codes. Fresh design against prose (§5.2/§11 name the table, §4 never
// gives its DDL), recovered from Baker Ally's own original -- see that
// migration's header. `value` semantics depend on `type`; the migration
// documents them.
export const discounts = pgTable("discounts", {
  id: uuid("id").primaryKey().defaultRandom(),
  code: text("code").unique(),
  name: text("name").notNull(),
  type: text("type").notNull(),
  value: integer("value").notNull().default(0),
  minOrderValue: integer("min_order_value").notNull().default(0),
  maxUses: integer("max_uses"),
  usesCount: integer("uses_count").notNull().default(0),
  isActive: boolean("is_active").notNull().default(true),
  startsAt: timestamp("starts_at", { withTimezone: true }),
  expiresAt: timestamp("expires_at", { withTimezone: true }),
  createdBy: uuid("created_by").references(() => users.id),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 7 (migrations/027) -- §4.8's literal DDL. One row per checkout =
// one payment = the one amount charged (§1.5). Written only by
// rpc_place_order (032), never by a bare Drizzle insert.
export const orderGroups = pgTable("order_groups", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  paymentMode: text("payment_mode").notNull(),
  paymentGateway: text("payment_gateway"),
  gatewayOrderId: text("gateway_order_id"),
  gatewayPaymentId: text("gateway_payment_id").unique(),
  discountId: uuid("discount_id").references(() => discounts.id),
  subtotal: integer("subtotal").notNull(),
  discountValue: integer("discount_value").notNull().default(0),
  deliveryFeeTotal: integer("delivery_fee_total").notNull().default(0),
  total: integer("total").notNull(),
  paymentStatus: text("payment_status").notNull().default("pending"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 7 (migrations/028) -- §4.8's literal DDL, both CHECK constraints
// included there (this schema doesn't repeat CHECKs, same as every other
// table here). One row per shop inside a checkout: own fulfillment, own
// slot, own status. `platformCommissionPct` is a numeric snapshot, so it
// comes back as a string through Drizzle -- same note as shops'.
export const orders = pgTable(
  "orders",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    orderGroupId: uuid("order_group_id")
      .notNull()
      .references(() => orderGroups.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    shopId: uuid("shop_id")
      .notNull()
      .references(() => shops.id),
    fulfillmentType: text("fulfillment_type").notNull(),
    deliveryFulfilledBy: text("delivery_fulfilled_by"),
    addressId: uuid("address_id").references(() => addresses.id),
    slotStart: timestamp("slot_start", { withTimezone: true }).notNull(),
    slotEnd: timestamp("slot_end", { withTimezone: true }).notNull(),
    riderId: uuid("rider_id").references(() => riders.id),
    status: text("status").notNull().default("pending"),
    subtotal: integer("subtotal").notNull(),
    discountValue: integer("discount_value").notNull().default(0),
    deliveryFee: integer("delivery_fee").notNull().default(0),
    platformCommissionPct: numeric("platform_commission_pct", { precision: 4, scale: 2 }).notNull(),
    total: integer("total").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("idx_orders_user_created").on(table.userId, table.createdAt),
    index("idx_orders_shop_created").on(table.shopId, table.createdAt),
  ],
);

// Sprint 7 (migrations/029) -- §4.8's literal DDL. §9's immutable
// order-item snapshot: product_name/variant_name/unit_price are copied at
// order time, never joined live afterwards.
export const orderItems = pgTable("order_items", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id, { onDelete: "cascade" }),
  variantId: uuid("variant_id")
    .notNull()
    .references(() => productVariants.id),
  productName: text("product_name").notNull(),
  variantName: text("variant_name").notNull(),
  quantity: integer("quantity").notNull(),
  unitPrice: integer("unit_price").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 7 (migrations/030) -- §4.8's literal DDL. Append-only; §7.5's
// live tracking subscribes to it from Sprint 9.
export const orderStatusHistory = pgTable("order_status_history", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id, { onDelete: "cascade" }),
  status: text("status").notNull(),
  note: text("note"),
  changedAt: timestamp("changed_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 7 (migrations/031) -- §4.9's literal DDL. Table only this sprint:
// nothing writes a row until Sprint 8's rpc_confirm_payment (§11). Added
// here now anyway, unlike shop_media/shop_blackout_dates which stayed out
// of this file until a route touched them, because the checkout work is
// what creates the obligation this table records -- keeping the definition
// next to orders/order_groups is where a reader will look for it.
export const shopLedgerEntries = pgTable("shop_ledger_entries", {
  id: uuid("id").primaryKey().defaultRandom(),
  shopId: uuid("shop_id")
    .notNull()
    .references(() => shops.id),
  orderId: uuid("order_id").references(() => orders.id),
  entryType: text("entry_type").notNull(),
  amount: integer("amount").notNull(),
  status: text("status").notNull().default("pending"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// Sprint 6 (migrations/025) -- see that file's header for where this
// table's DDL came from (Baker Ally's recovered v1 original, §9's reuse
// map). No route writes this yet (no admin curation UI exists this
// sprint) -- routes/recommendations.ts reads it, always finding zero rows
// in practice until that curation UI exists; see that file's header.
export const productCrossSell = pgTable(
  "product_cross_sell",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    sourceProductId: uuid("source_product_id")
      .notNull()
      .references(() => products.id, { onDelete: "cascade" }),
    recommendedProductId: uuid("recommended_product_id")
      .notNull()
      .references(() => products.id, { onDelete: "cascade" }),
    sortOrder: integer("sort_order").notNull().default(0),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    unique("product_cross_sell_source_product_id_recommended_product_id_key").on(
      table.sourceProductId,
      table.recommendedProductId,
    ),
  ],
);
