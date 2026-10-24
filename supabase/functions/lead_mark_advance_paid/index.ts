// Records an offline advance payment against a lead, which is the trigger that
// converts an 'inquiry' into a 'booked' lead and creates/links the real customer
// record. Runs on the service role so recorded_by_staff_id / created_by_staff_id /
// converted_by_staff_id can't be forged by the client -- the caller's identity is
// taken from their verified JWT, not from the request body.
import { jsonResponse, callerClient, serviceClient } from "../_shared/supabase.ts";

interface MarkAdvancePaidRequest {
  lead_id: string;
  amount: number;
  currency?: string;
  provider: "offline_cash" | "offline_upi";
  provider_reference?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const caller = callerClient(req);
  const { data: authData } = await caller.auth.getUser();
  if (!authData?.user) return jsonResponse({ error: "unauthenticated" }, 401);
  const staffId = authData.user.id;

  const body: MarkAdvancePaidRequest = await req.json();
  if (!body.lead_id || !body.amount || !body.provider) {
    return jsonResponse({ error: "lead_id, amount and provider are required" }, 400);
  }

  const db = serviceClient();

  const { data: staffRow } = await db.from("staff_users").select("id").eq("id", staffId).eq("status", "active").maybeSingle();
  if (!staffRow) return jsonResponse({ error: "caller is not an active staff user" }, 403);

  const { data: lead, error: leadError } = await db.from("leads").select("*").eq("id", body.lead_id).single();
  if (leadError || !lead) return jsonResponse({ error: "lead not found" }, 404);
  if (lead.stage === "booked") return jsonResponse({ error: "lead is already booked" }, 409);

  // Find-or-create the customer by phone (dedupe against anyone staff already added).
  let customerId: string;
  const { data: existingCustomer } = await db.from("customers").select("id").eq("phone", lead.contact_phone).maybeSingle();
  if (existingCustomer) {
    customerId = existingCustomer.id;
  } else {
    const { data: newCustomer, error: customerError } = await db
      .from("customers")
      .insert({
        full_name: lead.contact_name,
        phone: lead.contact_phone,
        email: lead.contact_email,
        created_by_staff_id: staffId,
      })
      .select("id")
      .single();
    if (customerError || !newCustomer) return jsonResponse({ error: customerError?.message ?? "customer creation failed" }, 500);
    customerId = newCustomer.id;
  }

  const { data: payment, error: paymentError } = await db
    .from("payment_transactions")
    .insert({
      lead_id: lead.id,
      provider: body.provider,
      provider_reference: body.provider_reference ?? null,
      recorded_by_staff_id: staffId,
      amount: body.amount,
      currency: body.currency ?? "INR",
      status: "succeeded",
      direction: "charge",
    })
    .select("id")
    .single();
  if (paymentError || !payment) return jsonResponse({ error: paymentError?.message ?? "payment record failed" }, 500);

  const { error: updateError } = await db
    .from("leads")
    .update({
      stage: "booked",
      converted_customer_id: customerId,
      converted_by_staff_id: staffId,
      advance_payment_transaction_id: payment.id,
      converted_at: new Date().toISOString(),
    })
    .eq("id", lead.id);
  if (updateError) return jsonResponse({ error: updateError.message }, 500);

  return jsonResponse({ lead_id: lead.id, customer_id: customerId, payment_transaction_id: payment.id, stage: "booked" });
});
