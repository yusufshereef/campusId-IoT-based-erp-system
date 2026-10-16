export function validateConfiguration(
  url?: string,
  key?: string,
): string | null {
  if (!url?.trim() || !key?.trim()) {
    return "Add your project URL and public key to .env.local, then restart the development server. See the README for setup instructions.";
  }
  try {
    const parsed = new URL(url);
    if (
      !["http:", "https:"].includes(parsed.protocol) ||
      parsed.username ||
      parsed.password
    )
      throw new Error("Invalid URL");
  } catch {
    return "The Supabase URL is invalid. Use the HTTP or HTTPS Project URL from your Supabase settings.";
  }
  if (key.startsWith("sb_secret_"))
    return "Use a Supabase publishable key in the browser. Secret keys belong on a trusted server.";
  return null;
}
