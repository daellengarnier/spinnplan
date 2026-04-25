import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const ONESIGNAL_APP_ID = "ba00c132-62a5-4f4a-b462-4d9f0ec6ceb0";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") || "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { name, date, start_time, end_time, type, body: customBody } = await req.json();

    const isShiftReminder = type === "shift_reminder";

    const heading = isShiftReminder ? name : `Neuer Anlass: ${name}`;

    let content: string;
    if (isShiftReminder && customBody) {
      content = customBody;
    } else {
      const dateStr = new Date(date + "T12:00:00").toLocaleDateString("de-CH", {
        weekday: "long",
        day: "numeric",
        month: "long",
      });
      content = `${dateStr} · ${start_time || ""}–${end_time || ""}. Trag dich jetzt für eine Schicht ein!`;
    }

    // Send to all subscribed users via OneSignal
    const onesignalRes = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Authorization: `Basic ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        included_segments: ["Subscribed Users"],
        headings: { en: heading, de: heading },
        contents: { en: content, de: content },
        url: "https://spinnplan-23.netlify.app",
      }),
    });

    const result = await onesignalRes.json();
    console.log("OneSignal response:", JSON.stringify(result));

    return new Response(JSON.stringify({ success: true, recipients: result.recipients || 0 }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
