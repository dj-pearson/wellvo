import { supabaseAdmin } from "../../shared/supabase.ts";
import { requireSystemAdmin } from "../../shared/admin-auth.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleAdminMetrics(req: Request, auth: AuthResult): Promise<Response> {
  const admin = await requireSystemAdmin(auth);
  if (!admin.ok) return admin.response;

  const url = new URL(req.url);
  const days = Math.max(1, Math.min(365, parseInt(url.searchParams.get("days") || "30", 10) || 30));

  const [metricsRes, seriesRes] = await Promise.all([
    supabaseAdmin.rpc("admin_dashboard_metrics"),
    supabaseAdmin.rpc("admin_daily_timeseries", { p_days: days }),
  ]);

  if (metricsRes.error) {
    return json({ error: "Failed to load metrics", details: metricsRes.error.message }, 500);
  }
  if (seriesRes.error) {
    return json({ error: "Failed to load timeseries", details: seriesRes.error.message }, 500);
  }

  return json({
    metrics: metricsRes.data,
    timeseries: seriesRes.data ?? [],
  });
}
