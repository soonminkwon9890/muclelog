import { createClient } from "@supabase/supabase-js";
import type { AnalysisResult } from "../types/biomechanics";

/**
 * Supabase 클라이언트 초기화
 */
let supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl) {
  throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL environment variable");
}

// URL 정규화: 이미 https://로 시작하면 그대로 사용, 아니면 추가
// 환경 변수에 이미 https://가 포함되어 있을 수 있으므로 중복 방지
if (!supabaseUrl.startsWith("http://") && !supabaseUrl.startsWith("https://")) {
  supabaseUrl = `https://${supabaseUrl}`;
} else if (supabaseUrl.startsWith("https://https://")) {
  // 중복된 https:// 제거
  supabaseUrl = supabaseUrl.replace(/^https:\/\/https:\/\//, "https://");
}

if (!supabaseServiceKey) {
  throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY environment variable");
}

// Server-side 작업을 위한 Service Role Key 사용
export const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

/**
 * workout_logs 테이블에 AI 분석 결과 업데이트
 * Single Source of Truth: workout_logs.ai_analysis_result만 사용
 */
export async function updateAnalysisResult(
  logId: string,
  userId: string,
  analysisResult: AnalysisResult
): Promise<void> {
  const { error } = await supabase
    .from("workout_logs")
    .update({
      ai_analysis_result: analysisResult,
      updated_at: new Date().toISOString(),
    })
    .eq("id", logId)
    .eq("user_id", userId);

  if (error) {
    console.error("Supabase 업데이트 오류:", error);
    throw new Error(`Failed to update analysis result: ${error.message}`);
  }
}
