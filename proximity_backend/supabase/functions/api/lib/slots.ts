// Sprint 4 (§7.2's NextSlotBadge). This is the minimal slot computation the
// Home badge actually needs -- NOT the full `GET /v1/shops/:id/fulfillment-
// slots` endpoint §4.6 describes (multi-day slot listing, capacity, blackout
// dates). That endpoint is still Sprint 7's job (checkout, per SPRINT_
// PLANNING.md §11) -- Sprint 2/3's write-ups already deferred it there, and
// nothing about a Home badge needs it: the badge only ever shows "the next
// (or current) slot today," never a picker. Building the real thing now
// would mean guessing at capacity/blackout-date UX this sprint doesn't spec,
// so this stays a narrow, single-purpose helper -- documented here rather
// than silently reusing the §4.6 name for something smaller than it implies.
//
// Deliberately does NOT look ahead to tomorrow if today's slots are all in
// the past (or the shop is closed today) -- returns `null`, and the badge
// just doesn't render (see NextSlotBadge.dart). A buyer scrolling Home late
// at night not seeing a countdown badge is an acceptable gap for this
// sprint; a real "next slot is tomorrow at 6 AM" case is exactly the kind
// of multi-day logic that belongs in Sprint 7's real endpoint, not here.
//
// Timezone: this codebase has no per-shop (or per-platform) timezone column
// anywhere in the schema, and every other date/time assumption so far
// (business hours, slot_window) has implicitly meant "India wall-clock
// time." Supabase Edge Functions run in UTC, so this file hardcodes the
// IST offset (+5:30) as the one interpretation of `platform_settings.
// slot_window`'s "06:00"/"24:00" strings and `shop_business_hours`'
// `opens_at`/`closes_at`. Revisit if this platform ever operates outside
// India -- there is currently no data model for "which timezone," so a
// single global constant is the honest minimum, not a placeholder for a
// per-shop lookup that doesn't exist yet.

const IST_OFFSET_MINUTES = 5 * 60 + 30;
const IST_OFFSET_MS = IST_OFFSET_MINUTES * 60_000;
const DAY_MS = 24 * 60 * 60_000;

export type SlotWindow = { start: string; end: string; slot_minutes: number };

export const DEFAULT_SLOT_WINDOW: SlotWindow = { start: "06:00", end: "24:00", slot_minutes: 120 };

export type ShopHoursRow = { opensAt: string | null; closesAt: string | null; isClosed: boolean } | null;

export type NextSlot = { slotStart: string; slotEnd: string } | null;

// "HH:MM" (or "24:00", which shop_business_hours' own CHECK constraint
// doesn't actually allow on closes_at, but slot_window's seeded end value
// uses it deliberately, per migrations/012 -- Date.parse can't handle it,
// hence manual parsing) -> minutes since midnight.
function parseHm(value: string): number {
  const [h, m] = value.split(":").map(Number);
  return h * 60 + (m || 0);
}

// Returns the real UTC instant for `minutesSinceIstMidnight` on the IST
// calendar day that contains `nowUtc` -- e.g. 360 (06:00) -> today's 06:00
// IST as an actual Date, regardless of what UTC date/hour the server
// happens to be running in.
function istMinutesToUtcDate(nowUtc: Date, minutesSinceIstMidnight: number): Date {
  const shiftedNowMs = nowUtc.getTime() + IST_OFFSET_MS;
  const istDayStartShiftedMs = Math.floor(shiftedNowMs / DAY_MS) * DAY_MS;
  return new Date(istDayStartShiftedMs + minutesSinceIstMidnight * 60_000 - IST_OFFSET_MS);
}

/** 0=Sunday..6=Saturday, matching Postgres's EXTRACT(DOW) (and shop_business_hours.weekday) -- computed in IST, not server-UTC. */
export function istWeekday(nowUtc: Date): number {
  const shiftedNowMs = nowUtc.getTime() + IST_OFFSET_MS;
  return new Date(Math.floor(shiftedNowMs / DAY_MS) * DAY_MS).getUTCDay();
}

/** Minutes-since-IST-midnight -> "HH:MM", for slot labels. */
function formatHm(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/** IST calendar date ("YYYY-MM-DD") that contains `nowUtc`. */
export function istDateString(nowUtc: Date): string {
  const shifted = new Date(nowUtc.getTime() + IST_OFFSET_MS);
  return shifted.toISOString().slice(0, 10);
}

/** Weekday (0=Sunday..6=Saturday, Postgres EXTRACT(DOW)) for an IST date string. */
export function istWeekdayForDate(dateStr: string): number {
  return new Date(`${dateStr}T00:00:00Z`).getUTCDay();
}

export type GeneratedSlot = {
  slotStart: string;
  slotEnd: string;
  label: string;
  available: boolean;
  /** Why this slot can't be picked -- §7.4 wants disabled slots shown with a reason, not hidden. */
  unavailableReason: string | null;
};

/**
 * Sprint 7: the real `GET /v1/shops/:id/fulfillment-slots` generator §4.6
 * describes -- a full day's candidate slots for one date, each annotated
 * with whether it can actually be picked and why not if it can't.
 *
 * This is what Sprint 4's `computeNextSlot` (below) was explicitly a
 * narrower stand-in for: that one answers "the next slot today" for the
 * Home badge and deliberately knows nothing about blackout dates or any day
 * but today. Both are kept -- the badge genuinely doesn't need a whole
 * day's list, and generating one per shop per Home card would be wasteful.
 *
 * Deliberately NOT handled, matching what this project actually has:
 *   * Capacity / booked counts. §4.6 says "if capacity limits are ever
 *     added" -- they haven't been; no table anywhere counts bookings per
 *     slot, so nothing here pretends to.
 *   * Per-shop timezones -- same single-country IST assumption this file's
 *     header already documents, unchanged.
 */
export function generateSlots(
  dateStr: string,
  nowUtc: Date,
  slotWindow: SlotWindow,
  hours: ShopHoursRow,
  isBlackout: boolean,
): GeneratedSlot[] {
  const windowStartMin = parseHm(slotWindow.start);
  const windowEndMin = parseHm(slotWindow.end);
  const slotMinutes = slotWindow.slot_minutes;
  if (slotMinutes <= 0 || windowEndMin <= windowStartMin) return [];

  // Midnight IST on the requested date, as a real UTC instant.
  const dayStartUtcMs = Date.parse(`${dateStr}T00:00:00Z`) - IST_OFFSET_MS;
  const closedReason = isBlackout
    ? "Shop closed on this date"
    : !hours || hours.isClosed || !hours.opensAt || !hours.closesAt
    ? "Shop closed on this day"
    : null;

  const opensMin = hours?.opensAt ? parseHm(hours.opensAt) : null;
  const closesMin = hours?.closesAt ? parseHm(hours.closesAt) : null;

  const slots: GeneratedSlot[] = [];
  for (let startMin = windowStartMin; startMin < windowEndMin; startMin += slotMinutes) {
    const endMin = startMin + slotMinutes;
    // A partial slot at the end of the window isn't offered at all -- an
    // order placed for "10pm-11pm" when the platform grid says 2 hours
    // would not match rpc_place_order's own duration check (migrations/032).
    if (endMin > windowEndMin) break;

    const startUtc = new Date(dayStartUtcMs + startMin * 60_000);
    const endUtc = new Date(dayStartUtcMs + endMin * 60_000);

    let reason: string | null = closedReason;
    if (!reason && (startMin < opensMin! || endMin > closesMin!)) {
      reason = "Outside shop hours";
    }
    if (!reason && startUtc.getTime() <= nowUtc.getTime()) {
      reason = "Too late for this slot";
    }

    slots.push({
      slotStart: startUtc.toISOString(),
      slotEnd: endUtc.toISOString(),
      label: `${formatHm(startMin)} - ${formatHm(endMin)}`,
      available: reason === null,
      unavailableReason: reason,
    });
  }

  return slots;
}

/**
 * The shop's current-or-next fulfillment slot today, clipped to its
 * business hours for today's weekday -- or `null` if the shop is closed
 * today, hasn't set hours at all, or every slot for today has already
 * passed. A slot only counts as "offered" if it fits entirely within the
 * shop's open hours (SPRINT_PLANNING.md §1.6's example: "a shop closed at
 * 9pm simply doesn't offer the 10pm slot").
 */
export function computeNextSlot(nowUtc: Date, slotWindow: SlotWindow, hours: ShopHoursRow): NextSlot {
  if (!hours || hours.isClosed || !hours.opensAt || !hours.closesAt) return null;

  const windowStartMin = parseHm(slotWindow.start);
  const windowEndMin = parseHm(slotWindow.end);
  const opensMin = parseHm(hours.opensAt);
  const closesMin = parseHm(hours.closesAt);
  const slotMinutes = slotWindow.slot_minutes;
  if (slotMinutes <= 0 || windowEndMin <= windowStartMin) return null;

  const shiftedNowMs = nowUtc.getTime() + IST_OFFSET_MS;
  const nowMinutesToday = Math.floor((shiftedNowMs % DAY_MS) / 60_000);

  for (let slotStartMin = windowStartMin; slotStartMin < windowEndMin; slotStartMin += slotMinutes) {
    const slotEndMin = Math.min(slotStartMin + slotMinutes, windowEndMin);
    if (slotStartMin < opensMin || slotEndMin > closesMin) continue; // doesn't fit inside today's business hours
    if (slotEndMin <= nowMinutesToday) continue; // already fully in the past

    return {
      slotStart: istMinutesToUtcDate(nowUtc, slotStartMin).toISOString(),
      slotEnd: istMinutesToUtcDate(nowUtc, slotEndMin).toISOString(),
    };
  }

  return null;
}
