import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Default fallback palette — mirrors AppTheme constants
// Cobalt Blue + Coral. Blue carries the technology, payment and delivery side;
// coral carries appetite. Kept in step with RemoteTheme.defaults in
// lib/utils/theme_service.dart and the app_theme row — three copies of one
// palette, and the row is what actually reaches the app.
const DEFAULT_THEME = {
  primaryColor: "#155EEF",     // Cobalt Blue
  secondaryColor: "#0B1220",   // Midnight Navy
  accentColor: "#FF6B5A",      // Coral
  backgroundColor: "#F8FAFC",  // Soft White
  errorColor: "#D92D20",
  successColor: "#12B76A",     // Emerald
  warningColor: "#F79009",
  priceColor: "#FF6B5A",       // Coral — prices should read warm, not technical
  textPrimary: "#101828",      // Charcoal
  textSecondary: "#475467",
  textLight: "#667085",
  borderColor: "#EAECF0",
  dividerColor: "#F2F4F7",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data, error } = await supabase
      .from("app_theme")
      .select("colors, updated_at")
      .eq("id", 1)
      .single();

    if (error || !data) {
      // Return defaults if table not yet seeded
      return new Response(
        JSON.stringify({ colors: DEFAULT_THEME, source: "default" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    // Merge with defaults so any missing keys fall back gracefully
    const merged = { ...DEFAULT_THEME, ...data.colors };

    return new Response(
      JSON.stringify({
        colors: merged,
        updated_at: data.updated_at,
        source: "db",
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          // Cache for 5 minutes — CDN-friendly
          "Cache-Control": "public, max-age=300, stale-while-revalidate=60",
        },
        status: 200,
      },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ colors: DEFAULT_THEME, source: "error", error: String(err) }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200, // Always 200 so app doesn't crash
      },
    );
  }
});
