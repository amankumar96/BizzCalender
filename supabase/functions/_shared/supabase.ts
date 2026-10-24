import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Service-role client: bypasses RLS, used for operations that must enforce their own
// authorization logic server-side (pricing math, double-booking guard, attribution
// fields that the client must never be able to forge).
export function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

// Caller-scoped client: respects RLS as the invoking user (staff or customer), used to
// confirm who is calling before doing privileged work with the service client.
export function callerClient(req: Request) {
  const authHeader = req.headers.get("Authorization") ?? "";
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
}

export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
