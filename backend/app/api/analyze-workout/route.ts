import { NextRequest, NextResponse } from "next/server";
import { analyzeWorkout } from "@/app/actions/analyze-workout";
import type {
  AnalyzeWorkoutRequest,
  AnalyzeWorkoutResponse,
} from "@/lib/types/biomechanics";

// Next.js가 이 라우트를 동적으로 처리하도록 강제 (빌드 타임 정적 생성 방지)
export const dynamic = "force-dynamic";

// Vercel 함수 실행 시간 제한 연장 (300초 = 5분, Pro 요금제)
export const maxDuration = 300;

/**
 * HTTP POST 엔드포인트: /api/analyze-workout
 * Flutter 앱에서 Motion Data와 Context를 받아 Gemini 분석 수행
 */
export async function POST(request: NextRequest) {
  try {
    // 1. Request Body 파싱
    const body: AnalyzeWorkoutRequest = await request.json();
    console.log("Received Body:", body);

    // 2. 입력 데이터 검증
    const validationError = validateRequest(body);
    if (validationError) {
      console.error("Validation Error:", validationError);
      return NextResponse.json(
        {
          success: false,
          error: validationError,
        } as AnalyzeWorkoutResponse,
        { status: 400 }
      );
    }

    // 2.5. Timestamp 자동 보정 (누락된 경우)
    if (body.motionData?.frames) {
      body.motionData.frames = body.motionData.frames.map(
        (frame: any, index: number) => {
          // timestamp가 없거나 유효하지 않으면 자동 보정
          if (
            frame.timestamp === undefined ||
            frame.timestamp === null ||
            typeof frame.timestamp !== "number"
          ) {
            // 30fps 기준: index * 33ms = 초 단위로 변환
            const timestampMs = index * 33;
            const timestampSeconds = timestampMs / 1000.0;
            console.log(
              `⚠️ [Auto-fill] Frame ${index}: timestamp 누락, 자동 보정: ${timestampSeconds}s (${timestampMs}ms)`
            );
            return {
              ...frame,
              timestamp: timestampSeconds,
            };
          }
          return frame;
        }
      );
    }

    // 2.6. 데이터 다운샘플링 (고정 개수 샘플링: 최대 50개)
    if (body.motionData?.frames) {
      const originalFrameCount = body.motionData.frames.length;
      const targetFrameCount = 50; // 고정 목표 프레임 수

      if (originalFrameCount > targetFrameCount) {
        // 샘플링 간격 계산: 전체 프레임을 50개로 나누기
        const samplingRate = Math.ceil(originalFrameCount / targetFrameCount);

        // 균일한 간격으로 프레임 추출
        body.motionData.frames = body.motionData.frames.filter(
          (_: any, index: number) => index % samplingRate === 0
        );

        // 최대 50개로 제한 (반올림으로 인해 초과할 수 있음)
        if (body.motionData.frames.length > targetFrameCount) {
          body.motionData.frames = body.motionData.frames.slice(
            0,
            targetFrameCount
          );
        }

        const sampledFrameCount = body.motionData.frames.length;
        console.log(
          `📊 [Downsampling] 프레임 수 감소: ${originalFrameCount} → ${sampledFrameCount} (샘플링 간격: ${samplingRate}, ${(
            (sampledFrameCount / originalFrameCount) *
            100
          ).toFixed(1)}%)`
        );
      } else {
        console.log(
          `📊 [Downsampling] 프레임 수가 ${targetFrameCount}개 이하이므로 샘플링 생략: ${originalFrameCount}개`
        );
      }
    }

    // 3. Server Action 호출
    const result = await analyzeWorkout(
      body.context,
      body.motionData,
      body.userId,
      body.logId
    );

    // 4. 성공 응답 반환
    return NextResponse.json(
      {
        success: true,
        data: result,
      } as AnalyzeWorkoutResponse,
      { status: 200 }
    );
  } catch (error: any) {
    console.error("API Route 오류:", error);

    // 5. 에러 응답 반환
    return NextResponse.json(
      {
        success: false,
        error: error.message || "Internal server error",
      } as AnalyzeWorkoutResponse,
      { status: 500 }
    );
  }
}

/**
 * OPTIONS 핸들러 (CORS Preflight)
 */
export async function OPTIONS() {
  return new NextResponse(null, {
    status: 200,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}

/**
 * Request Body 검증
 */
function validateRequest(body: any): string | null {
  // Context 검증
  if (!body.context) {
    return "context is required";
  }

  if (!["UpperBody", "LowerBody", "FullBody"].includes(body.context.bodyPart)) {
    return `Invalid bodyPart: ${body.context.bodyPart}`;
  }

  if (
    !["Isotonic", "Isometric", "Isokinetic"].includes(body.context.contraction)
  ) {
    return `Invalid contraction: ${body.context.contraction}`;
  }

  if (
    !body.context.exerciseName ||
    typeof body.context.exerciseName !== "string"
  ) {
    return "exerciseName is required and must be a string";
  }

  // Motion Data 검증
  if (!body.motionData) {
    return "motionData is required";
  }

  if (!Array.isArray(body.motionData.frames)) {
    return "motionData.frames must be an array";
  }

  if (body.motionData.frames.length === 0) {
    return "motionData.frames must not be empty";
  }

  // 첫 번째 프레임 검증
  const firstFrame = body.motionData.frames[0];
  // timestamp 검증 제거: 누락 시 자동 보정 로직에서 처리

  if (!Array.isArray(firstFrame.landmarks)) {
    return "Each frame must have landmarks array";
  }

  // 첫 번째 랜드마크 검증
  if (firstFrame.landmarks.length > 0) {
    const firstLandmark = firstFrame.landmarks[0];
    if (
      !firstLandmark.type ||
      typeof firstLandmark.x !== "number" ||
      typeof firstLandmark.y !== "number" ||
      typeof firstLandmark.z !== "number" ||
      typeof firstLandmark.likelihood !== "number"
    ) {
      return "Each landmark must have type, x, y, z, and likelihood";
    }
  }

  // userId, logId 검증
  if (!body.userId || typeof body.userId !== "string") {
    return "userId is required and must be a string";
  }

  if (!body.logId || typeof body.logId !== "string") {
    return "logId is required and must be a string";
  }

  return null;
}
