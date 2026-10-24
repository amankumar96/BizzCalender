// Creates a charge/order with whichever gateway is configured for this company, and
// writes the initial payment_transactions row. Gateway choice is deferred, so this
// stub only establishes the contract -- fill in the provider-specific API call once
// Razorpay/Stripe/etc. is picked.
import { jsonResponse, callerClient, serviceClient } from "../_shared/supabase.ts";

interface CreateIntentRequest {
  booking_id: string;
  amount: number;
  currency?: string;
  provider: string; // e.g. 'razorpay' | 'stripe'
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const caller = callerClient(req);
  const { data: authData } = await caller.auth.getUser();
  if (!authData?.user) return jsonResponse({ error: "unauthenticated" }, 401);

  const body: CreateIntentRequest = await req.json();
  if (!body.booking_id || !body.amount || !body.provider) {
    return jsonResponse({ error: "booking_id, amount and provider are required" }, 400);
  }

  // TODO: call the chosen gateway's order/intent-creation API here and capture its
  // reference id + any client-facing params (e.g. Razorpay order_id + key_id).
  const providerReference = `pending-${crypto.randomUUID()}`;

  const db = serviceClient();
  const { data: txn, error } = await db
    .from("payment_transactions")
    .insert({
      booking_id: body.booking_id,
      provider: body.provider,
      provider_reference: providerReference,
      amount: body.amount,
      currency: body.currency ?? "INR",
      status: "created",
      direction: "charge",
    })
    .select("id, provider_reference")
    .single();

  if (error || !txn) return jsonResponse({ error: error?.message ?? "could not create payment transaction" }, 500);
  return jsonResponse({ payment_transaction_id: txn.id, provider_reference: txn.provider_reference });
});
