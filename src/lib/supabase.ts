import { createClient } from "@supabase/supabase-js";
import { validateConfiguration } from "./configuration";

const url = import.meta.env.VITE_SUPABASE_URL?.trim();
const key = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim();

export const configurationError = validateConfiguration(url, key);
export const configured = configurationError === null;

export const supabase =
  configured && url && key ? createClient(url, key) : null;
