// 한끗루틴 Web Push 발송 Edge Function
// 호출: POST { user_id | user_ids, title, body?, url? }
// 권한: 관리자 계정 JWT 또는 service_role 키만 발송 가능
//   (anon 키는 클라이언트에 공개돼 있어, 그것만으로 발송을 허용하면
//    누구나 임의 사용자에게 푸시를 보낼 수 있음)
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const ADMINS = ["dev@youthvoice.or.kr", "yv@youthvoice.or.kr"];

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:dev@youthvoice.or.kr",
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!,
);

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST만 지원해요" });

  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const isServiceRole = token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!isServiceRole) {
    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error || !user || !ADMINS.includes(user.email ?? "")) {
      return json(403, { error: "관리자만 발송할 수 있어요" });
    }
  }

  let body: { user_id?: string; user_ids?: string[]; title?: string; body?: string; url?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "JSON 본문이 필요해요" });
  }
  const targets = body.user_ids ?? (body.user_id ? [body.user_id] : null);
  if (!targets?.length || !body.title) {
    return json(400, { error: "user_id(또는 user_ids)와 title은 필수예요" });
  }

  const { data: subs, error: subErr } = await supabase
    .from("push_subscriptions")
    .select("id,endpoint,p256dh,auth")
    .in("user_id", targets);
  if (subErr) return json(500, { error: subErr.message });

  const payload = JSON.stringify({
    title: body.title,
    body: body.body ?? "",
    url: body.url ?? "/youthit-routine/",
  });

  let sent = 0, removed = 0, failed = 0;
  await Promise.all((subs ?? []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        payload,
      );
      sent++;
    } catch (e) {
      const status = (e as { statusCode?: number }).statusCode;
      // 410 Gone / 404: 구독이 만료됐거나 사용자가 브라우저에서 알림을 꺼버린 경우 → 정리
      if (status === 404 || status === 410) {
        await supabase.from("push_subscriptions").delete().eq("id", s.id);
        removed++;
      } else {
        failed++;
      }
    }
  }));

  return json(200, { sent, removed, failed, total: subs?.length ?? 0 });
});
