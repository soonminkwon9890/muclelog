"use server";

import { GoogleGenerativeAI } from "@google/generative-ai";
import { buildContextAwarePrompt } from "../../utils/prompts";
import { updateAnalysisResult } from "@/lib/supabase/client";
import type {
  WorkoutContext,
  MotionData,
  AnalysisResult,
  EnhancedAnalysisResult,
  BiomechanicsLogic,
} from "@/lib/types/biomechanics";

/**
 * Gemini API를 사용하여 운동 분석 수행
 */
export async function analyzeWorkout(
  context: WorkoutContext,
  motionData: MotionData,
  userId: string,
  logId: string
): Promise<AnalysisResult> {
  // 1. Context 검증
  if (!["UpperBody", "LowerBody", "FullBody"].includes(context.bodyPart)) {
    throw new Error(`Invalid bodyPart: ${context.bodyPart}`);
  }

  if (!["Isotonic", "Isometric", "Isokinetic"].includes(context.contraction)) {
    throw new Error(`Invalid contraction: ${context.contraction}`);
  }

  // 2. Motion Data 검증
  if (!motionData.frames || motionData.frames.length === 0) {
    throw new Error("Motion data is empty");
  }

  // 3. Gemini API 키 확인
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("GEMINI_API_KEY is not set");
  }

  // 4. Gemini 프롬프트 생성
  const prompt = buildContextAwarePrompt(context, motionData);

  // 5. Gemini API 호출 (Lazy Initialization: 요청 시점에만 초기화)
  // 빌드 타임 초기화 방지를 위해 함수 내부에서만 인스턴스 생성
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-pro" });

  let geminiResponse: AnalysisResult;
  let retryCount = 0;
  const maxRetries = 3;

  while (retryCount < maxRetries) {
    try {
      const result = await model.generateContent(prompt);
      const response = await result.response;
      const text = response.text();

      // 6. JSON 파싱
      geminiResponse = parseGeminiResponse(text);

      // 6.1 향상된 결과 검증
      if (isEnhancedResult(geminiResponse)) {
        validateEnhancedResult(geminiResponse);
      }
      break;
    } catch (error: any) {
      retryCount++;
      console.error(
        `Gemini API 호출 실패 (시도 ${retryCount}/${maxRetries}):`,
        error
      );

      if (retryCount >= maxRetries) {
        // Fallback: 기본값 반환
        console.warn("Gemini API 실패, Fallback 결과 반환");
        geminiResponse = createFallbackResult(context);
        break;
      }

      // Exponential Backoff
      await new Promise((resolve) =>
        setTimeout(resolve, Math.pow(2, retryCount) * 1000)
      );
    }
  }

  // 7. 결과 검증
  validateAnalysisResult(geminiResponse!);

  // 8. Supabase에 저장
  try {
    await updateAnalysisResult(logId, userId, geminiResponse!);
    console.log(`✅ Analysis result saved to Supabase (logId: ${logId})`);
  } catch (error: any) {
    console.error("Supabase 저장 실패:", error);
    // 저장 실패해도 결과는 반환 (재시도 가능)
    throw error; // 에러를 다시 throw하여 호출자가 처리할 수 있도록
  }

  return geminiResponse!;
}

/**
 * [수정됨] 강력한 정규식을 사용한 Gemini 응답 파싱
 * 마크다운 코드 블록이나 텍스트 사이에서 JSON 객체만 추출합니다.
 */
function parseGeminiResponse(text: string): AnalysisResult {
  // 마크다운 코드 블록 안의 JSON 또는 중괄호 {} 로 감싸진 원본 JSON을 찾는 정규식
  const jsonRegex = /```(?:json)?\s*([\s\S]*?)\s*```|(\{[\s\S]*\})/i;
  const match = text.match(jsonRegex);

  let jsonStr = text;
  if (match) {
    // 그룹 1 (마크다운 내부 내용) 또는 그룹 2 (중괄호 내용) 선택
    jsonStr = (match[1] || match[2] || text).trim();
  }

  try {
    const parsed = JSON.parse(jsonStr);
    return parsed as AnalysisResult;
  } catch (error) {
    console.error("❌ JSON 파싱 실패:", error);
    console.error("원본 텍스트:", text);
    console.error("추출된 텍스트:", jsonStr);
    // 앱을 죽이지 말고, 의미 있는 에러를 던져서 재시도 로직이 동작하게 함
    throw new Error("Failed to parse Gemini response as JSON");
  }
}

/**
 * 향상된 결과인지 확인
 */
function isEnhancedResult(
  result: AnalysisResult
): result is EnhancedAnalysisResult {
  return (
    "kinematic_analysis" in result &&
    "joint_stats" in result &&
    "muscle_scores" in result
  );
}

/**
 * 향상된 결과 검증
 */
function validateEnhancedResult(result: EnhancedAnalysisResult): void {
  // kinematic_analysis 검증
  if (!result.kinematic_analysis) {
    throw new Error("kinematic_analysis is required");
  }

  const { active_joints, ignored_joints } = result.kinematic_analysis;

  if (!Array.isArray(active_joints) || !Array.isArray(ignored_joints)) {
    throw new Error(
      "kinematic_analysis.active_joints and ignored_joints must be arrays"
    );
  }

  // active_joints와 joint_stats 일치 확인
  for (const joint of active_joints) {
    if (
      result.joint_stats[joint] === null ||
      result.joint_stats[joint] === undefined
    ) {
      throw new Error(
        `Active joint "${joint}" must have joint_stats, but got null/undefined`
      );
    }

    const jointStat = result.joint_stats[joint];
    if (jointStat) {
      // JointStats 구조 검증
      if (
        typeof jointStat.rom_degrees !== "number" ||
        typeof jointStat.stability_score !== "number" ||
        typeof jointStat.contribution_score !== "number"
      ) {
        throw new Error(
          `Joint stat for "${joint}" must have rom_degrees, stability_score, and contribution_score as numbers`
        );
      }

      // 점수 범위 검증
      if (
        jointStat.stability_score < 0 ||
        jointStat.stability_score > 100 ||
        jointStat.contribution_score < 0 ||
        jointStat.contribution_score > 100
      ) {
        throw new Error(
          `Joint stat scores for "${joint}" must be between 0 and 100`
        );
      }
    }
  }

  // ignored_joints는 null이어야 함
  for (const joint of ignored_joints) {
    if (result.joint_stats[joint] !== null) {
      console.warn(
        `Ignored joint "${joint}" should have null joint_stats, but got:`,
        result.joint_stats[joint]
      );
    }
  }

  // muscle_scores와 joint_stats 의존성 확인
  for (const [muscle, score] of Object.entries(result.muscle_scores)) {
    if (score && score.dependency_joint) {
      const jointStat = result.joint_stats[score.dependency_joint];
      if (!jointStat) {
        console.warn(
          `Muscle "${muscle}" depends on joint "${score.dependency_joint}" but joint_stats is null/undefined`
        );
      }

      // 근육 점수 범위 검증
      if (
        typeof score.score !== "number" ||
        score.score < 0 ||
        score.score > 100
      ) {
        throw new Error(
          `Muscle score for "${muscle}" must be a number between 0 and 100`
        );
      }
    } else if (score && !score.dependency_joint) {
      console.warn(
        `Muscle "${muscle}" has a score but no dependency_joint specified`
      );
    }
  }

  // detected_movement_pattern 검증
  if (!result.kinematic_analysis.detected_movement_pattern) {
    throw new Error("kinematic_analysis.detected_movement_pattern is required");
  }
}

/**
 * [수정됨] 자동 보정이 포함된 결과 검증
 * 에러를 발생시키는 대신, 잘못된 데이터를 수정하여 DB 저장을 보장합니다.
 */
function validateAnalysisResult(result: AnalysisResult): void {
  // scores 객체가 없으면 기본값 생성
  if (!result.scores) {
    console.warn("⚠️ 'scores' 객체가 없습니다. 기본값을 생성합니다.");
    result.scores = { overall_score: 0 } as any;
  }

  // overall_score가 숫자가 아니면 0으로 설정
  if (typeof result.scores.overall_score !== "number") {
    console.warn("⚠️ 'overall_score'가 숫자가 아닙니다. 0으로 설정합니다.");
    result.scores.overall_score = 0;
  }

  // 세부 점수 필드 보정 (문자열이나 "N/A"가 오면 null로 강제 변환)
  const scoreKeys = [
    "rom_score",
    "stability_score",
    "velocity_score",
    "symmetry_score",
    "power_score",
    "isolation_score",
  ];

  for (const key of scoreKeys) {
    const val = (result.scores as any)[key];
    // 값이 존재하지만 숫자가 아닌 경우 (예: "N/A") -> null로 변환
    if (val !== null && val !== undefined && typeof val !== "number") {
      console.warn(
        `⚠️ 점수 '${key}'의 타입이 올바르지 않습니다 (${typeof val}: ${val}). null로 강제 변환합니다.`
      );
      (result.scores as any)[key] = null;
    }
  }

  // applied_logics가 없거나 배열이 아니면 빈 배열로 설정
  if (!result.applied_logics || !Array.isArray(result.applied_logics)) {
    console.warn(
      "⚠️ 'applied_logics'가 없거나 유효하지 않습니다. 빈 배열로 설정합니다."
    );
    result.applied_logics = [];
  }

  // 디버깅용 성공 로그
  console.log("✅ 분석 결과 검증 및 보정 완료.");
}

/**
 * Fallback 결과 생성 (Gemini API 실패 시)
 */
function createFallbackResult(context: WorkoutContext): AnalysisResult {
  const selectedLogics = getDefaultLogics(context);

  return {
    applied_logics: selectedLogics,
    scores: {
      overall_score: 50.0,
      rom_score: selectedLogics.includes("ROM_Check") ? 50.0 : null,
      stability_score: selectedLogics.includes("Stability") ? 50.0 : null,
      velocity_score: selectedLogics.includes("Velocity_Consistency")
        ? 50.0
        : null,
      symmetry_score: selectedLogics.includes("Symmetry") ? 50.0 : null,
      power_score: selectedLogics.includes("Power_Output") ? 50.0 : null,
      isolation_score: selectedLogics.includes("Muscle_Isolation")
        ? 50.0
        : null,
    },
    // feedback은 선택적 (새로운 형식에서는 없을 수 있음)
    feedback: {
      summary: "분석을 완료할 수 없어 기본값을 반환했습니다.",
      details: "Gemini API 호출에 실패했습니다. 네트워크 연결을 확인해주세요.",
    },
  };
}

/**
 * 기본 로직 선택 (Fallback용)
 */
function getDefaultLogics(context: WorkoutContext): BiomechanicsLogic[] {
  if (context.contraction === "Isometric") {
    return ["Stability", "Muscle_Isolation"];
  } else if (context.contraction === "Isokinetic") {
    return ["Velocity_Consistency", "Symmetry"];
  } else {
    return ["ROM_Check", "Symmetry"];
  }
}
