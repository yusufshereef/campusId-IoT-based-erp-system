const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-campusid-device-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function serviceHeaders(serviceRoleKey: string) {
  return {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const secret = request.headers.get("x-campusid-device-secret")?.trim();
  if (!secret || secret.length < 16) {
    return jsonResponse({ error: "Device authentication failed" }, 401);
  }
  const body = await request.json().catch(() => null) as {
    device_id?: string;
    action?: string;
    command_id?: string;
    success?: boolean;
    template_id?: number;
    error_message?: string;
  } | null;
  if (!body?.device_id || !["poll", "complete"].includes(body.action || "")) {
    return jsonResponse({ error: "Invalid command request" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return jsonResponse({ error: "Command service is not configured" }, 500);
  const headers = serviceHeaders(serviceRoleKey);
  const deviceResponse = await fetch(
    `${url}/rest/v1/devices?device_code=eq.${encodeURIComponent(body.device_id)}&select=id,secret_hash&limit=1`,
    { headers },
  );
  const devices = deviceResponse.ok ? await deviceResponse.json() : [];
  const device = devices[0] as { id: string; secret_hash: string } | undefined;
  if (!device || !constantTimeEqual(await sha256Hex(secret), device.secret_hash)) {
    return jsonResponse({ error: "Device authentication failed" }, 401);
  }

  const rpc = body.action === "poll" ? "claim_device_command" : "complete_device_command";
  const parameters = body.action === "poll"
    ? { p_device_id: device.id }
    : {
        p_command_id: body.command_id,
        p_device_id: device.id,
        p_success: body.success === true,
        p_template_id: body.template_id ?? null,
        p_error_message: body.error_message ?? null,
      };
  const response = await fetch(`${url}/rest/v1/rpc/${rpc}`, {
    method: "POST",
    headers,
    body: JSON.stringify(parameters),
  });
  if (!response.ok) return jsonResponse({ error: "Command operation failed" }, 502);
  const result = await response.json();
  return jsonResponse({ command: result });
});
