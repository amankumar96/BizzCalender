// Generic inbound webhook endpoint. No gateway is chosen yet, so the provider is
// resolved from the URL path (/payment_webhook_handler/razorpay, /.../stripe, ...)
// and each provider gets its own thin signature-verification branch. Writes to
// payment_webhooks_log first for idempotency (unique on provider+event_id), then
// updates payment_transactions / bookings.
import { jsonResponse, serviceClient } from "../_shared/supabase.ts";

function verifySignature(_provider: string, _rawBody: string, _headers: Headers): boolean {
  // TODO: once a gateway is chosen, verify its webhook signature here
  // (e.g. Razorpay: HMAC-SHA256 of rawBody with the webhook secret, compared to the
  // X-Razorpay-Signature header). Reject with 400 on mismatch before processing.
  return true;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const provider = new URL(req.url).pathname.split("/").pop() ?? "unknown";
  const rawBody = await req.text();

  if (!verifySignature(provider, rawBody, req.headers)) {
    return jsonResponse({ error: "invalid signature" }, 400);
  }

  const payload = JSON.parse(rawBody);
  const eventId: string | undefined = payload.id ?? payload.event_id;
  if (!eventId) return jsonResponse({ error: "payload missing an event id" }, 400);

  const db = serviceClient();

  // Idempotency: if we've already logged this event, acknowledge without reprocessing.
  const { data: existing } = await db
    .from("payment_webhooks_log")
    .select("id, processed_at")
    .eq("provider", provider)
    .eq("event_id", eventId)
    .maybeSingle();
  if (existing?.processed_at) return jsonResponse({ status: "already processed" });

  if (!existing) {
    await db.from("payment_webhooks_log").insert({ provider, event_id: eventId, payload });
  }

  // TODO: map the provider's payload shape to { provider_reference, status, amount }
  // once a gateway is chosen. For now this expects a normalized shape for testing.
  const providerReference: string | undefined = payload.provider_reference ?? payload.order_id;
  const status: string = payload.status ?? "succeeded";

  if (providerReference) {
    const { data: txn } = await db
      .from("payment_transactions")
      .update({ status, raw_payload: payload, updated_at: new Date().toISOString() })
      .eq("provider", provider)
      .eq("provider_reference", providerReference)
      .select("booking_id")
      .maybeSingle();

    if (txn?.booking_id && status === "succeeded") {
      await db.from("bookings").update({ status: "confirmed" }).eq("id", txn.booking_id);
    }
  }

  await db.from("payment_webhooks_log").update({ processed_at: new Date().toISOString() }).eq("provider", provider).eq("event_id", eventId);

  return jsonResponse({ status: "processed" });
});
