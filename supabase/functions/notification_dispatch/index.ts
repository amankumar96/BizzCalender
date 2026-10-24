// Consumes queued notifications rows and sends them via the appropriate channel
// provider. Provider wiring (SMS/WhatsApp/email/push) is deferred -- this establishes
// the dispatch loop and status bookkeeping.
import { jsonResponse, serviceClient } from "../_shared/supabase.ts";

async function sendViaChannel(channel: string, payload: Record<string, unknown>): Promise<boolean> {
  // TODO: wire real providers, e.g. Twilio for sms/whatsapp, SendGrid for email, FCM for push.
  console.log(`[notification_dispatch] would send via ${channel}:`, payload);
  return true;
}

Deno.serve(async (_req: Request) => {
  const db = serviceClient();
  const { data: queued, error } = await db.from("notifications").select("*").eq("status", "queued").limit(50);
  if (error) return jsonResponse({ error: error.message }, 500);

  let sent = 0;
  let failed = 0;
  for (const n of queued ?? []) {
    const ok = await sendViaChannel(n.channel, n.payload);
    await db
      .from("notifications")
      .update({ status: ok ? "sent" : "failed", sent_at: ok ? new Date().toISOString() : null })
      .eq("id", n.id);
    ok ? sent++ : failed++;
  }

  return jsonResponse({ sent, failed, total: (queued ?? []).length });
});
