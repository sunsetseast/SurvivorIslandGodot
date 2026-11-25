// GoTrue validates the bearer and performs permanent Auth deletion. No target ID
// crosses the client API. Foreign keys delete application rows in that transaction.
const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

function reply(status: number, code: string) {
  return Response.json({ code }, { status, headers: cors });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });
  if (request.method !== "POST") return reply(405, "method");
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, "sign_in_required");
  let passwordProof: string | undefined;
  let deleted = false;
  try {
    const declaredLength = Number(request.headers.get("Content-Length") ?? 0);
    if (declaredLength > 512) return reply(400, "invalid_form");
    const raw = await request.text();
    if (raw.length > 512) return reply(400, "invalid_form");
    const input = JSON.parse(raw);
    if (typeof input?.password !== "string" || input.password.length < 1 ||
        input.password.length > 72 || Object.keys(input).some((key) => key !== "password")) {
      return reply(400, "invalid_form");
    }
    // The RPC requires a live session row. A signed-out token cannot authorize
    // deletion during its remaining JWT validity.
    const headers = { authorization, apikey: anon, "Content-Type": "application/json" };
    const session = await fetch(url + "/rest/v1/rpc/player_data", {
      method: "POST", headers, body: '{"action":"profile"}',
    });
    await session.body?.cancel();
    if (!session.ok) return reply(session.status >= 500 ? 503 : 401, "sign_in_required");
    const userResponse = await fetch(url + "/auth/v1/user", { headers });
    if (!userResponse.ok) return reply(userResponse.status >= 500 ? 503 : 401, "sign_in_required");
    const user = await userResponse.json();
    const auth = await fetch(url + "/auth/v1/token?grant_type=password", {
      method: "POST",
      headers: { apikey: anon, "Content-Type": "application/json" },
      body: JSON.stringify({ email: user.email, password: input.password }),
    });
    if (!auth.ok) {
      await auth.body?.cancel();
      return reply(auth.status === 429 ? 429 : auth.status >= 500 ? 503 : 403, "reauthentication_failed");
    }
    const fresh = await auth.json();
    passwordProof = typeof fresh.access_token === "string" ? fresh.access_token : undefined;
    if (!user.email_confirmed_at || !passwordProof || fresh.user?.id !== user.id) {
      return reply(403, "reauthentication_failed");
    }
    const removed = await fetch(url + "/auth/v1/admin/users/" + encodeURIComponent(user.id), {
      method: "DELETE",
      headers: { apikey: serviceRole, authorization: "Bearer " + serviceRole },
    });
    await removed.body?.cancel();
    deleted = removed.ok || removed.status === 404;
    return deleted ? reply(200, "deleted") : reply(503, "delete_unavailable");
  } catch (error) {
    return error instanceof SyntaxError ? reply(400, "invalid_form") : reply(503, "delete_unavailable");
  } finally {
    if (passwordProof && !deleted) {
      await fetch(url + "/auth/v1/logout?scope=local", {
        method: "POST",
        headers: { apikey: anon, authorization: "Bearer " + passwordProof },
        signal: AbortSignal.timeout(4000),
      }).then((response) => response.body?.cancel()).catch(() => {});
    }
  }
});
