/**
 * 생체역학 분석을 위한 TypeScript 타입 정의
 */

/**
 * 운동 컨텍스트
 * 사용자가 선택한 운동의 부위와 수축 타입
 */
export interface WorkoutContext {
  bodyPart: "UpperBody" | "LowerBody" | "FullBody";
  contraction: "Isotonic" | "Isometric" | "Isokinetic";
  exerciseName: string;
}

/**
 * MediaPipe Pose Landmark
 * 포즈 감지에서 추출된 단일 랜드마크 데이터
 */
export interface PoseLandmark {
  type: string; // 'nose', 'leftShoulder', 'rightHip', etc.
  x: number; // 0.0 ~ 1.0 (정규화된 좌표)
  y: number; // 0.0 ~ 1.0
  z: number; // 깊이 (상대값)
  likelihood: number; // 0.0 ~ 1.0 (신뢰도)
}

/**
 * Motion Data
 * 프레임별 포즈 랜드마크 데이터 배열
 */
export interface MotionData {
  frames: Array<{
    timestamp: number; // 프레임 타임스탬프 (초)
    landmarks: PoseLandmark[]; // 33개 MediaPipe 랜드마크 (likelihood >= 0.6만 포함)
  }>;
  visible_joints?: string[]; // 현재 영상에 보이는 관절 목록 (예: ["shoulder", "elbow", "knee"])
}

/**
 * 6가지 핵심 생체역학 로직
 */
export type BiomechanicsLogic =
  | "ROM_Check"
  | "Stability"
  | "Velocity_Consistency"
  | "Symmetry"
  | "Power_Output"
  | "Muscle_Isolation";

/**
 * 분석 점수
 * 각 로직별 점수 (0-100), null (해당 로직이 선택되지 않았거나 데이터가 없는 경우)
 * ⚠️ "N/A" 문자열은 사용하지 않음 (타입 안전성)
 */
export interface AnalysisScores {
  overall_score: number; // 0-100
  rom_score: number | null;
  stability_score: number | null;
  velocity_score: number | null;
  symmetry_score: number | null;
  power_score: number | null;
  isolation_score: number | null;
}

/**
 * 핵심 메트릭스 (Core Metrics)
 * 6가지 생체역학 로직의 점수
 */
export interface CoreMetrics {
  rom_score: number | null;
  stability_score: number | null;
  tempo_score: number | null;
  symmetry_score: number | null;
  posture_score: number | null;
  intensity_score: number | null;
}

/**
 * 표준화된 분석 결과
 * 새로운 출력 형식 (안전성 및 데이터 타입 이슈 해결)
 */
export interface StandardizedAnalysisResult {
  motion_type: "isotonic" | "isometric" | "unknown";
  overall_score: number;
  core_metrics: CoreMetrics;
  detected_faults: string[]; // 결함 식별 배열 (의료법 리스크 방지)
  detailed_muscle_usage: Record<string, number | null>;
  rom_data: Record<string, number | null>;
  // feedback_message removed for safety
}

/**
 * 운동학적 분석 결과
 * 실제 motionData 기반으로 감지된 움직임 패턴
 */
export interface KinematicAnalysis {
  detected_movement_pattern: string; // AI가 감지한 실제 움직임
  active_joints: string[]; // ROM > 15도인 관절
  ignored_joints: string[]; // 움직임 없거나 안 보이는 관절
}

/**
 * 관절 통계
 * 실제 측정된 물리량
 */
export interface JointStats {
  rom_degrees: number; // 실제 측정된 각도 (도)
  stability_score: number; // 0-100
  contribution_score: number; // 0-100
}

/**
 * 근육 점수
 * 관절 점수에 의존하는 근육 활성도
 */
export interface MuscleScore {
  score: number; // 0-100
  dependency_joint?: string; // 의존하는 관절
}

/**
 * 분석 결과
 * Gemini가 계산한 최종 분석 결과
 * 하위 호환성을 위해 feedback은 선택적 (새로운 형식에서는 없을 수 있음)
 */
export interface AnalysisResult {
  applied_logics: BiomechanicsLogic[]; // 최소 2개, 최대 3개
  scores: AnalysisScores;
  feedback?: {
    summary: string;
    details: string;
  };
}

/**
 * 향상된 분석 결과
 * 운동학적 분석, 관절 통계, 근육 점수 포함
 */
export interface EnhancedAnalysisResult extends AnalysisResult {
  kinematic_analysis: KinematicAnalysis;
  joint_stats: Record<string, JointStats | null>;
  muscle_scores: Record<string, MuscleScore | null>;
  debug_info?: {
    detected_rom_degrees?: number;
    focus_joints?: string[];
  };
}

/**
 * API 요청 본문
 */
export interface AnalyzeWorkoutRequest {
  context: WorkoutContext;
  motionData: MotionData;
  userId: string;
  logId: string;
}

/**
 * API 응답
 */
export interface AnalyzeWorkoutResponse {
  success: boolean;
  data?: AnalysisResult;
  error?: string;
}
