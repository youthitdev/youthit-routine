// 한끗루틴 AI 루틴 리포트 Edge Function
// 호출: POST (본인 JWT 필수) — Anthropic API 키를 서버에만 보관하고, 클라이언트는 이 함수만 호출
// 프롬프트는 클라이언트가 만들어 보내지만(본인 통계 요약뿐, 조작해도 본인만 영향받음),
// 키는 절대 클라이언트에 노출되지 않음
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

  let prompt: string;
  try {
    const body = await req.json();
    prompt = body?.prompt;
  } catch (_e) {
    return json(400, { error: "잘못된 요청이에요" });
  }
  if (!prompt || typeof prompt !== "string" || prompt.length > 2000) {
    return json(400, { error: "잘못된 요청이에요" });
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json(500, { error: "AI 리포트 기능이 아직 설정되지 않았어요" });

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-sonnet-5",
      max_tokens: 1000,
      system: '탈학교 청소년의 생활 루틴 형성을 돕는 따뜻한 AI 코치예요. 아래 JSON 형식으로만 응답하세요.\n{"analysis":"루틴 분석 (2~3문장)","books":[{"title":"책 제목","author":"저자","reason":"이유 한 문장"},{"title":"책 제목","author":"저자","reason":"이유"}]}',
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    return json(502, { error: "AI 호출 실패: " + errText });
  }
  const data = await res.json();
  return json(200, { text: data.content?.[0]?.text ?? "" });
});
