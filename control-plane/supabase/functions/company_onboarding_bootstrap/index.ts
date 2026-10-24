// Provisions a brand-new tenant Supabase project for a newly registered company via
// the Supabase Management API, applies core/* + the chosen industry's migrations, and
// registers the result in control_companies. The Management API call and migration
// push are the parts that depend on account-specific setup (org id, access token,
// CLI availability in this runtime) -- left as clearly marked TODOs so this can be
// wired up against the real Supabase account when onboarding goes live.
import { jsonResponse, serviceClient } from "../../../../supabase/functions/_shared/supabase.ts";

interface OnboardRequest {
  company_name: string;
  industry_code: string; // must match a folder under supabase/migrations/industries/
  admin_auth_user_id: string; // the person who will administer this company
  region?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  const body: OnboardRequest = await req.json();
  if (!body.company_name || !body.industry_code || !body.admin_auth_user_id) {
    return jsonResponse({ error: "company_name, industry_code and admin_auth_user_id are required" }, 400);
  }

  const db = serviceClient();

  const { data: company, error } = await db
    .from("control_companies")
    .insert({
      name: body.company_name,
      industry_code: body.industry_code,
      supabase_project_url: "pending",
      supabase_anon_key: "pending",
      supabase_service_role_key_secret_ref: "pending",
      status: "provisioning",
    })
    .select("id")
    .single();
  if (error || !company) return jsonResponse({ error: error?.message ?? "could not create registry row" }, 500);

  try {
    // TODO: call the Supabase Management API to create a new project:
    //   POST https://api.supabase.com/v1/projects
    //   { organization_id, name: body.company_name, region: body.region ?? 'ap-south-1', ... }
    //   using a Management API access token stored as a control-plane secret.
    //
    // TODO: once the project is ready, apply migrations in order:
    //   supabase/migrations/core/*.sql
    //   supabase/migrations/industries/<body.industry_code>/*.sql
    //   via `supabase db push` against the new project, or by running each file
    //   through the Management API's SQL execution endpoint.
    //
    // TODO: store the new project's URL + anon key on the control_companies row, and
    // the service role key via a secrets manager (never as plaintext in the table) --
    // supabase_service_role_key_secret_ref should point at that secret, not hold it.

    throw new Error("Management API provisioning not yet wired up -- see TODOs above");
  } catch (provisionError) {
    await db.from("control_companies").update({ status: "provisioning" }).eq("id", company.id);
    return jsonResponse({ company_id: company.id, status: "provisioning", note: String(provisionError) }, 202);
  }
});
