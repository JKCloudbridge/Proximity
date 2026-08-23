import { boolean, index, integer, pgTable, text, timestamp, unique, uuid } from "npm:drizzle-orm/pg-core";

// Mirrors migrations/001-005 -- see those files for constraints/comments
// this schema doesn't repeat (RLS policies, CHECK constraints, extension
// setup). Sprint 1 subset only: users, addresses, categories. shops,
// shop_team_members, riders, products, etc. land in their own migrations
// and get added here in the sprint that creates them -- keep this file
// growing in step with migrations/, never ahead of it.
//
// Note: `location GEOGRAPHY(Point,4326)` on `addresses` has no clean Drizzle
// pg-core column type -- it's declared as a raw SQL column here isn't
// possible without drizzle-orm's `customType`, which Sprint 1 doesn't need
// yet (nothing reads/writes it from the backend this sprint; address
// creation posts lat/lng and the DB layer will need a custom type once a
// route actually does something with `location` -- flagged in
// Sprint 1.md rather than guessed at here).

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
