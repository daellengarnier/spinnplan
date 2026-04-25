import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") || "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

webpush.setVapidDetails("mailto:info@kulturspinnerei.ch", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

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
    const title = isShiftReminder ? name : `Neuer Anlass: ${name}`;

    let body: string;
    if (isShiftReminder && customBody) {
      body = customBody;
    } else {
      const dateStr = new Date(date + "T12:00:00").toLocaleDateString("de-CH", {
        weekday: "long",
        day: "numeric",
        month: "long",
      });
      body = `${dateStr} · ${start_time || ""}–${end_time || ""}. Trag dich jetzt für eine Schicht ein!`;
    }

    const payload = JSON.stringify({
      title,
      body,
      url: "https://spinnplan-23.netlify.app",
    });

    // Get all push subscriptions from Supabase
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: subs } = await sb.from("push_subscriptions").select("*");

    let sent = 0;
    let failed = 0;
    const stale: string[] = [];

    for (const sub of subs || []) {
      const pushSub = {
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth },
      };
      try {
        await webpush.sendNotification(pushSub, payload);
        sent++;
      } catch (err: any) {
        failed++;
        // Remove expired/invalid subscriptions (410 Gone, 404 Not Found)
        if (err.statusCode === 410 || err.statusCode === 404) {
          stale.push(sub.endpoint);
        }
        console.error(`Push failed for ${sub.endpoint}:`, err.statusCode || err.message);
      }
    }

    // Clean up stale subscriptions
    if (stale.length > 0) {
      await sb.from("push_subscriptions").delete().in("endpoint", stale);
    }

    console.log(`Push sent: ${sent}, failed: ${failed}, cleaned: ${stale.length}`);

    return new Response(JSON.stringify({ success: true, sent, failed }), {
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
