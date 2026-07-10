// 한끗루틴 Web Push 발송 Edge Function
// 호출: POST { user_id | user_ids | (target:'all') | (target:'routine', routine_id), title, body?, url? }
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

// 토큰이 진짜 service 키인지 검증: 문자열 비교(레거시 JWT) 또는
// 그 키로 관리자 전용 API가 실제로 호출되는지 확인 (신형 sb_secret 키 대응)
async function isServiceKey(token: string): Promise<boolean> {
  if (!token) return false;
  if (token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) return true;
  try {
    const probe = createClient(Deno.env.get("SUPABASE_URL")!, token);
    const { error } = await probe.auth.admin.listUsers({ page: 1, perPage: 1 });
    return !error;
  } catch {
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST만 지원해요" });

  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!(await isServiceKey(token))) {
    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error || !user || !ADMINS.includes(user.email ?? "")) {
      return json(403, { error: "관리자만 발송할 수 있어요" });
    }
  }

  let body: {
    user_id?: string; user_ids?: string[]; target?: "all" | "routine"; routine_id?: number;
    title?: string; body?: string; url?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "JSON 본문이 필요해요" });
  }
  if (!body.title) return json(400, { error: "title은 필수예요" });

  let subs: { id: number; endpoint: string; p256dh: string; auth: string }[] | null = null;
  let subErr: { message: string } | null = null;

  if (body.target === "all") {
    ({ data: subs, error: subErr } = await supabase
      .from("push_subscriptions").select("id,endpoint,p256dh,auth"));
  } else if (body.target === "routine") {
    if (!body.routine_id) return json(400, { error: "routine_id가 필요해요" });
    const { data: approved, error: rpErr } = await supabase
      .from("routine_participants").select("user_id")
      .eq("routine_id", body.routine_id).eq("status", "approved");
    if (rpErr) return json(500, { error: rpErr.message });
    const ids = (approved ?? []).map((p) => p.user_id);
    ({ data: subs, error: subErr } = ids.length
      ? await supabase.from("push_subscriptions").select("id,endpoint,p256dh,auth").in("user_id", ids)
      : { data: [], error: null });
  } else {
    const targets = body.user_ids ?? (body.user_id ? [body.user_id] : null);
    if (!targets?.length) return json(400, { error: "user_id·user_ids 또는 target이 필요해요" });
    ({ data: subs, error: subErr } = await supabase
      .from("push_subscriptions").select("id,endpoint,p256dh,auth").in("user_id", targets));
  }
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
