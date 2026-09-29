// Supabase client bootstrap for the VectorTrack AI dashboard.
//
// The public runtime config comes from FastAPI (/config) so the URL and anon
// key live in exactly one place: the server's environment. Only the anon key
// is ever used in the browser — the service-role key stays on the server.

import { createClient } from '@supabase/supabase-js';

const REFRESH_WINDOW_MS = 30_000;

let configPromise = null;
let clientPromise = null;

export async function loadPublicConfig() {
    if (!configPromise) {
        configPromise = (async () => {
            const res = await fetch('/config', { headers: { Accept: 'application/json' } });
            if (!res.ok) {
                throw new Error(`Could not load /config (HTTP ${res.status}).`);
            }
            const cfg = await res.json();
            if (!cfg.supabase_url || !cfg.supabase_anon_key) {
                throw new Error(
                    'Supabase is not configured on the server. Set SUPABASE_URL and SUPABASE_ANON_KEY.'
                );
            }
            return cfg;
        })();
    }
    return configPromise;
}

export async function getSupabase() {
    if (!clientPromise) {
        clientPromise = (async () => {
            const cfg = await loadPublicConfig();
            return createClient(cfg.supabase_url, cfg.supabase_anon_key, {
                auth: {
                    persistSession: true,
                    autoRefreshToken: true,
                    detectSessionInUrl: true,
                    flowType: 'pkce',
                },
            });
        })();
    }
    return clientPromise;
}

export async function getSession() {
    const supabase = await getSupabase();
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    return data.session || null;
}

/** Current access token, refreshed first when it is about to expire. */
export async function getAccessToken() {
    const supabase = await getSupabase();
    const { data } = await supabase.auth.getSession();
    const session = data ? data.session : null;
    if (!session) return null;

    const expiresAt = session.expires_at ? session.expires_at * 1000 : 0;
    if (expiresAt && expiresAt - Date.now() < REFRESH_WINDOW_MS) {
        const refreshed = await refreshAccessToken();
        if (refreshed) return refreshed;
    }
    return session.access_token;
}

export async function refreshAccessToken() {
    const supabase = await getSupabase();
    const { data, error } = await supabase.auth.refreshSession();
    if (error || !data.session) return null;
    return data.session.access_token;
}

export async function signInWithGoogle() {
    const supabase = await getSupabase();
    const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.origin + window.location.pathname },
    });
    if (error) throw error;
}

export async function signOutUser() {
    const supabase = await getSupabase();
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
}

export function onAuthStateChange(callback) {
    let subscription = null;
    getSupabase()
        .then((supabase) => {
            const { data } = supabase.auth.onAuthStateChange((event, session) => callback(event, session));
            subscription = data.subscription;
        })
        .catch(() => {});
    return () => {
        if (subscription) subscription.unsubscribe();
    };
}

/** Newest detections for the signed-in user (RLS keeps this to their rows). */
export async function fetchRecentDetections(limit = 20) {
    const supabase = await getSupabase();
    const { data, error } = await supabase
        .from('detections')
        .select('id, class, confidence, source, media_type, created_at')
        .order('created_at', { ascending: false })
        .limit(limit);
    if (error) throw error;
    return data || [];
}
