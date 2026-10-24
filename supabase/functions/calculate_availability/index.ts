// Wraps fn_calendar_slots for multi-resource aggregate checks that plain PostgREST
// RPC can't express cleanly, e.g. "is there a free 2-photographer + 2-videographer
// combo on this date" for a package booking. Single-resource lookups can call
// fn_calendar_slots directly via PostgREST RPC and don't need this function.
import { jsonResponse, serviceClient } from "../_shared/supabase.ts";

interface ResourceRequirement { resource_id: string; slot_definition_id: string }
interface AvailabilityRequest {
  requirements: ResourceRequirement[];
  date_from: string;
  date_to: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);
  const body: AvailabilityRequest = await req.json();
  if (!body.requirements?.length || !body.date_from || !body.date_to) {
    return jsonResponse({ error: "requirements, date_from and date_to are required" }, 400);
  }

  const db = serviceClient();

  // For each resource, fetch its per-day state, then intersect: a date only counts as
  // fully available if every required resource is 'available' that day.
  const perResourceStates = await Promise.all(
    body.requirements.map((r) =>
      db.rpc("fn_calendar_slots", {
        p_resource_id: r.resource_id,
        p_slot_definition_id: r.slot_definition_id,
        p_date_from: body.date_from,
        p_date_to: body.date_to,
      }),
    ),
  );

  for (const result of perResourceStates) {
    if (result.error) return jsonResponse({ error: result.error.message }, 500);
  }

  const byDate = new Map<string, { starts_at: string; ends_at: string; states: string[] }>();
  perResourceStates.forEach((result) => {
    for (const row of result.data ?? []) {
      const key = `${row.slot_date}|${row.starts_at}|${row.ends_at}`;
      const entry = byDate.get(key) ?? { starts_at: row.starts_at, ends_at: row.ends_at, states: [] };
      entry.states.push(row.state);
      byDate.set(key, entry);
    }
  });

  const combined = Array.from(byDate.entries()).map(([key, entry]) => {
    const slot_date = key.split("|")[0];
    const allAvailable = entry.states.every((s) => s === "available");
    const anyBooked = entry.states.some((s) => s === "booked");
    return {
      slot_date,
      starts_at: entry.starts_at,
      ends_at: entry.ends_at,
      state: allAvailable ? "available" : anyBooked ? "booked" : "unavailable",
    };
  });

  return jsonResponse({ slots: combined });
});
