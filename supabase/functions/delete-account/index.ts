// 한끗루틴 회원 탈퇴 Edge Function
// 호출: POST (본인 JWT 필수) — 본인 계정만 삭제 가능
// 처리: 스토리지의 본인 파일(증빙서류·인증사진) 삭제 → auth 계정 삭제
//       (DB 기록은 auth.users ON DELETE CASCADE로 자동 정리,
//        posts/letters는 SET NULL로 글만 남고 작성자 연결이 끊김)
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "POST만 지원해요" });

  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const { data: { user }, error: authErr } = await supabase.auth.getUser(token);
  if (authErr || !user) return json(401, { error: "로그인이 필요해요" });

  // 0) 삭제 후에는 프로필을 읽을 수 없으므로 역할·닉네임을 미리 읽어둠
  //    (익명 로그에는 역할만 저장, 닉네임은 관리자 푸시에만 쓰고 어디에도 남기지 않음)
  let role: string | null = null;
  let name: string | null = null;
  try {
    const { data: prof } = await supabase.from("profiles").select("role,name").eq("id", user.id).single();
    role = prof?.role ?? null;
    name = prof?.name ?? null;
  } catch (_e) { /* 프로필 조회 실패가 탈퇴 자체를 막지는 않음 */ }

  // 1) 스토리지의 본인 파일 삭제 (증빙서류는 민감정보라 반드시 정리)
  for (const bucket of ["verify-docs", "cert-photos"]) {
    try {
      const { data: files } = await supabase.storage.from(bucket).list(user.id, { limit: 1000 });
      if (files?.length) {
        await supabase.storage.from(bucket).remove(files.map((f) => `${user.id}/${f.name}`));
      }
    } catch (_e) { /* 파일 정리 실패가 탈퇴 자체를 막지는 않음 */ }
  }

  // 2) 계정 삭제 (연결된 DB 기록은 CASCADE로 함께 삭제)
  const { error: delErr } = await supabase.auth.admin.deleteUser(user.id);
  if (delErr) return json(500, { error: delErr.message });

  // 3) 삭제 성공 후에만 익명 탈퇴 로그 + 운영진 푸시 (실패해도 탈퇴는 이미 완료)
  try {
    await supabase.from("withdrawal_log").insert({ role });
    const roleLabel = role === "kkutjjang" ? "끗짱" : "청소년";
    await supabase.rpc("notify_admins", {
      push_title: "회원 탈퇴 알림",
      push_body: `${roleLabel} "${name ?? "알 수 없음"}"님이 탈퇴했어요.`,
    });
  } catch (_e) { /* 로그·알림 실패는 무시 */ }

  return json(200, { ok: true });
});
