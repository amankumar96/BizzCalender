// Creates the full event/appointment booking for a lead that is already 'booked'
// (date locked by an offline advance via lead_mark_advance_paid), then backfills the
// advance payment's booking_id so it's traceable lead -> payment -> booking end to end.
import { jsonResponse, callerClient, serviceClient } from "../_shared/supabase.ts";

interface ConvertRequest {
  lead_id: string;
  event_type: string;
  starts_at: string;
  ends_at: string;
  slot_definition_id: string;
  package_id?: string;
  services?: { service_id: string; rate_card_id?: string; quantity?: number }[];
  addons?: { addon_id: string; quantity?: number }[];
  resources: { resource_id: string; role_label?: string; starts_at: string; ends_at: string }[];
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const caller = callerClient(req);
  const { data: authData } = await caller.auth.getUser();
  if (!authData?.user) return jsonResponse({ error: "unauthenticated" }, 401);

  const body: ConvertRequest = await req.json();
  if (!body.lead_id || !body.resources?.length) return jsonResponse({ error: "lead_id and resources are required" }, 400);

  const db = serviceClient();
  const { data: lead, error: leadError } = await db.from("leads").select("*").eq("id", body.lead_id).single();
  if (leadError || !lead) return jsonResponse({ error: "lead not found" }, 404);
  if (lead.stage !== "booked") return jsonResponse({ error: "lead must be in 'booked' stage (advance paid) before conversion" }, 409);
  if (lead.booking_id) return jsonResponse({ error: "lead already has a booking" }, 409);
  if (!lead.converted_customer_id) return jsonResponse({ error: "lead has no linked customer" }, 409);

  // Delegate the actual booking creation (pricing resolution + resource assignment +
  // exclusion-constraint race guard) to create_booking so the logic isn't duplicated.
  const createBookingUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/create_booking`;
  const resp = await fetch(createBookingUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: req.headers.get("Authorization") ?? "",
    },
    body: JSON.stringify({
      customer_id: lead.converted_customer_id,
      created_by_staff_id: lead.converted_by_staff_id,
      lead_id: lead.id,
      event_type: body.event_type,
      starts_at: body.starts_at,
      ends_at: body.ends_at,
      slot_definition_id: body.slot_definition_id,
      package_id: body.package_id,
      services: body.services,
      addons: body.addons,
      resources: body.resources,
    }),
  });

  const result = await resp.json();
  return jsonResponse(result, resp.status);
});
