// Invoked right after a customer's first successful OTP login. Backfills
// customers.auth_user_id if a staff member already created a customer record for this
// phone number, instead of letting a duplicate customer row be created.
import { jsonResponse, callerClient, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const caller = callerClient(req);
  const { data: authData } = await caller.auth.getUser();
  if (!authData?.user?.phone) return jsonResponse({ error: "unauthenticated or missing phone" }, 401);

  const db = serviceClient();
  const userId = authData.user.id;
  const phone = authData.user.phone;

  const { data: existing } = await db.from("customers").select("id, auth_user_id").eq("phone", phone).maybeSingle();

  if (existing && !existing.auth_user_id) {
    await db.from("customers").update({ auth_user_id: userId }).eq("id", existing.id);
    return jsonResponse({ customer_id: existing.id, status: "linked" });
  }
  if (existing) {
    return jsonResponse({ customer_id: existing.id, status: "already_linked" });
  }

  const { data: created, error } = await db
    .from("customers")
    .insert({ auth_user_id: userId, full_name: authData.user.phone, phone })
    .select("id")
    .single();
  if (error || !created) return jsonResponse({ error: error?.message ?? "could not create customer" }, 500);
  return jsonResponse({ customer_id: created.id, status: "created" });
});
