// Creates a booking: resolves pricing (package override vs itemized sum), inserts the
// booking + its line items + resource assignments, and relies on the GiST exclusion
// constraint on booking_resources as the final, authoritative double-booking guard
// (a pre-check query gives a friendlier error, but the constraint is what's actually
// race-safe under concurrent requests).
import { jsonResponse, callerClient, serviceClient } from "../_shared/supabase.ts";

interface ServiceLine { service_id: string; rate_card_id?: string; quantity?: number }
interface AddonLine { addon_id: string; quantity?: number }
interface ResourceLine { resource_id: string; role_label?: string; starts_at: string; ends_at: string }

interface CreateBookingRequest {
  customer_id: string;
  created_by_staff_id?: string;
  lead_id?: string;
  event_type: string;
  starts_at: string;
  ends_at: string;
  slot_definition_id: string;
  package_id?: string;
  services?: ServiceLine[];
  addons?: AddonLine[];
  resources: ResourceLine[];
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const caller = callerClient(req);
  const { data: authData } = await caller.auth.getUser();
  if (!authData?.user) return jsonResponse({ error: "unauthenticated" }, 401);

  const body: CreateBookingRequest = await req.json();
  if (!body.customer_id || !body.slot_definition_id || !body.resources?.length) {
    return jsonResponse({ error: "customer_id, slot_definition_id and resources are required" }, 400);
  }

  const db = serviceClient();

  // Pre-check for overlap on every resource (friendly error before hitting the
  // exclusion constraint; NOT a substitute for it under concurrency).
  for (const r of body.resources) {
    const { data: clashes, error } = await db
      .from("booking_resources")
      .select("id")
      .eq("resource_id", r.resource_id)
      .neq("status", "cancelled")
      .lt("starts_at", r.ends_at)
      .gt("ends_at", r.starts_at);
    if (error) return jsonResponse({ error: error.message }, 500);
    if (clashes && clashes.length > 0) {
      return jsonResponse({ error: `resource ${r.resource_id} is already booked for that window` }, 409);
    }
  }

  // Resolve pricing.
  let totalAmount = 0;
  const serviceInserts: Record<string, unknown>[] = [];
  const addonInserts: Record<string, unknown>[] = [];

  if (body.package_id) {
    const { data: pkg, error } = await db.from("packages").select("package_price, currency").eq("id", body.package_id).single();
    if (error || !pkg) return jsonResponse({ error: "package not found" }, 400);
    totalAmount = Number(pkg.package_price);

    const { data: items } = await db.from("package_items").select("service_id, quantity, rate_card_id").eq("package_id", body.package_id);
    for (const item of items ?? []) {
      let unitPrice = 0;
      if (item.rate_card_id) {
        const { data: rc } = await db.from("rate_cards").select("price").eq("id", item.rate_card_id).single();
        unitPrice = rc ? Number(rc.price) : 0;
      }
      serviceInserts.push({ service_id: item.service_id, rate_card_id: item.rate_card_id, quantity: item.quantity, unit_price: unitPrice });
    }
  } else {
    for (const line of body.services ?? []) {
      let unitPrice = 0;
      if (line.rate_card_id) {
        const { data: rc } = await db.from("rate_cards").select("price").eq("id", line.rate_card_id).single();
        unitPrice = rc ? Number(rc.price) : 0;
      }
      const qty = line.quantity ?? 1;
      totalAmount += unitPrice * qty;
      serviceInserts.push({ service_id: line.service_id, rate_card_id: line.rate_card_id, quantity: qty, unit_price: unitPrice });
    }
  }

  for (const line of body.addons ?? []) {
    const { data: addon } = await db.from("addons").select("price").eq("id", line.addon_id).single();
    const unitPrice = addon ? Number(addon.price) : 0;
    const qty = line.quantity ?? 1;
    totalAmount += unitPrice * qty;
    addonInserts.push({ addon_id: line.addon_id, quantity: qty, unit_price: unitPrice });
  }

  // Insert booking.
  const { data: booking, error: bookingError } = await db
    .from("bookings")
    .insert({
      customer_id: body.customer_id,
      created_by_staff_id: body.created_by_staff_id ?? null,
      lead_id: body.lead_id ?? null,
      status: "confirmed",
      event_type: body.event_type,
      starts_at: body.starts_at,
      ends_at: body.ends_at,
      slot_definition_id: body.slot_definition_id,
      package_id: body.package_id ?? null,
      total_amount: totalAmount,
    })
    .select()
    .single();

  if (bookingError || !booking) return jsonResponse({ error: bookingError?.message ?? "booking insert failed" }, 500);

  const bookingId = booking.id;

  if (serviceInserts.length) {
    const { error } = await db.from("booking_services").insert(serviceInserts.map((s) => ({ ...s, booking_id: bookingId })));
    if (error) {
      await db.from("bookings").delete().eq("id", bookingId);
      return jsonResponse({ error: error.message }, 500);
    }
  }
  if (addonInserts.length) {
    const { error } = await db.from("booking_addons").insert(addonInserts.map((a) => ({ ...a, booking_id: bookingId })));
    if (error) {
      await db.from("bookings").delete().eq("id", bookingId);
      return jsonResponse({ error: error.message }, 500);
    }
  }

  // Resource assignment: this insert is where the GiST exclusion constraint actually
  // rejects a race-condition double-booking (two concurrent requests for the same
  // resource/window). On conflict, roll back the booking we just created.
  const { error: resourceError } = await db.from("booking_resources").insert(
    body.resources.map((r) => ({
      booking_id: bookingId,
      resource_id: r.resource_id,
      role_label: r.role_label ?? null,
      starts_at: r.starts_at,
      ends_at: r.ends_at,
    })),
  );
  if (resourceError) {
    await db.from("bookings").delete().eq("id", bookingId);
    const isConflict = resourceError.message.includes("exclude") || resourceError.code === "23P01";
    return jsonResponse({ error: isConflict ? "resource double-booked" : resourceError.message }, isConflict ? 409 : 500);
  }

  // If this booking was created against a lead, backfill the link both ways.
  if (body.lead_id) {
    await db.from("leads").update({ booking_id: bookingId }).eq("id", body.lead_id);
    await db.from("payment_transactions").update({ booking_id: bookingId }).eq("lead_id", body.lead_id).is("booking_id", null);
  }

  return jsonResponse({ booking_id: bookingId, total_amount: totalAmount });
});
