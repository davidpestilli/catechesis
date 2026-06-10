export const env = {
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL?.trim() ?? '',
  supabaseAnonKey: import.meta.env.VITE_SUPABASE_ANON_KEY?.trim() ?? '',
  workerUrl: import.meta.env.VITE_CLOUDFLARE_WORKER_URL?.trim() ?? '',
  siteName: import.meta.env.VITE_SITE_NAME?.trim() ?? 'Catechesis',
}

export const hasSupabaseConfig = Boolean(env.supabaseUrl && env.supabaseAnonKey)
