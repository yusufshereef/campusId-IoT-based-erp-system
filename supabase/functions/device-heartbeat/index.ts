const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-campusid-device-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

type HeartbeatPayload = {
  device_id: string;
  firmware_version: string;
  sensor_ready: boolean;
  pending_event_count: number;
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function isValidPayload(value: unknown): value is HeartbeatPayload {
  if (!value || typeof value !== "object") return false;
  const payload = value as Partial<HeartbeatPayload>;
  return (
    typeof payload.device_id === "string" &&
    /^[a-z0-9][a-z0-9-]*$/.test(payload.device_id) &&
    payload.device_id.length <= 96 &&
    typeof payload.firmware_version === "string" &&
    payload.firmware_version.length <= 64 &&
    typeof payload.sensor_ready === "boolean" &&
    Number.isInteger(payload.pending_event_count) &&
    payload.pending_event_count >= 0 &&
    payload.pending_event_count <= 1000000
  );
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
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
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const secret = request.headers.get("x-campusid-device-secret")?.trim();
  if (!secret || secret.length < 16) {
    return jsonResponse({ error: "Device authentication failed" }, 401);
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON payload" }, 400);
  }
  if (!isValidPayload(payload)) {
    return jsonResponse({ error: "Invalid heartbeat payload" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Heartbeat service is not configured" }, 500);
  }

  const baseUrl = `${supabaseUrl}/rest/v1/devices`;
  const lookup = await fetch(
    `${baseUrl}?device_code=eq.${encodeURIComponent(payload.device_id)}&select=id,secret_hash&limit=1`,
    { headers: serviceHeaders(serviceRoleKey) },
  );
  if (!lookup.ok) {
    return jsonResponse({ error: "Device lookup failed" }, 502);
  }
  const devices = (await lookup.json()) as Array<{
    id: string;
    secret_hash: string;
  }>;
  const device = devices[0];
  if (
    !device ||
    !constantTimeEqual(await sha256Hex(secret), device.secret_hash)
  ) {
    return jsonResponse({ error: "Device authentication failed" }, 401);
  }

  const update = await fetch(`${baseUrl}?id=eq.${device.id}`, {
    method: "PATCH",
    headers: {
      ...serviceHeaders(serviceRoleKey),
      Prefer: "return=minimal",
    },
    body: JSON.stringify({
      firmware_version: payload.firmware_version,
      sensor_ready: payload.sensor_ready,
      pending_event_count: payload.pending_event_count,
      last_seen_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }),
  });
  if (!update.ok) {
    return jsonResponse({ error: "Heartbeat update failed" }, 502);
  }

  return jsonResponse({
    acknowledged: true,
    device_id: payload.device_id,
    server_time: new Date().toISOString(),
  });
});
