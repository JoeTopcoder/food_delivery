// NCB Banks List Edge Function (Test Mode)
// TODO: Replace with real NCB banks/branches API if available

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Simulated NCB branches (replace with real data if available)
  const banks = [
    {
      name: "National Commercial Bank",
      code: "NCB",
      branches: [
        { name: "Half Way Tree", code: "HWT" },
        { name: "New Kingston", code: "NK" },
        { name: "Downtown Kingston", code: "DTK" },
        { name: "Spanish Town", code: "ST" },
      ],
    },
  ];

  return json({ banks });
});
