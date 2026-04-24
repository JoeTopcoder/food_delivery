import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Default fallback palette — mirrors AppTheme constants
const DEFAULT_THEME = {
  primaryColor: "#7C3AED",
  secondaryColor: "#004E89",
  accentColor: "#E74C3C",
  backgroundColor: "#F7F8FA",
  errorColor: "#E63946",
  successColor: "#06A77D",
  warningColor: "#FFA630",
  priceColor: "#E74C3C",
  textPrimary: "#111827",
  textSecondary: "#374151",
  textLight: "#4B5563",
  borderColor: "#E5E7EB",
  dividerColor: "#F3F4F6",
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
