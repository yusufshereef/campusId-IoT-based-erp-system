import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL?.trim();
const key = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();

export const configured = Boolean(url && key);
export const configurationError = configured
  ? null
  : "Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env.local, then restart Vite.";

export const supabase =
  configured && url && key ? createClient(url, key) : null;
