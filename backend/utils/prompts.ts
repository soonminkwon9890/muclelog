import type {
  WorkoutContext,
  MotionData,
  BiomechanicsLogic,
} from "../lib/types/biomechanics";

/**
 * Gemini 프롬프트 생성 함수 (Refactored for Pure Biomechanics)
 * 목적: 운동 종목(Label)에 의존하지 않는 순수 데이터 기반 분석
 */

/**
 * 데이터 기반 분석 원칙 (Pure Mechanics Logic)
 */
function buildDataDrivenInstruction(context: WorkoutContext): string {
  return `
## 순수 생체역학 분석 원칙 (Pure Biomechanics Protocol)

### 🚨 규칙 0: BLIND ANALYSIS (운동 이름 무시)
- **CRITICAL**: 사용자가 선택한 운동 이름("${context.exerciseName}")을 **완전히 무시**하십시오.
- AI는 지금 이 사람이 무슨 운동을 하려고 했는지 모른다고 가정하십시오.
- 오직 **"지금 어느 관절이 움직이고 있는가?"** (Active Joints)만 분석의 기준이 됩니다.
- 예: 사용자가 "스쿼트"를 선택했더라도, 영상 속 사람이 팔만 움직인다면 **"상체 움직임(Elbow Flexion)"**으로 간주하고 그에 맞는 점수를 부여해야 합니다. "스쿼트를 안 해서 0점"이 아니라 "팔 움직임이 효율적인지"를 평가하십시오.

### Step 1: Prime Mover Identification (주동근 자동 식별)
1. 전체 프레임 데이터를 스캔하여 각 관절의 **Total Angle Delta (총 각도 변화량)**를 계산하십시오.
2. 변화량이 **20도 이상**인 관절을 **"Prime Movers(주동 관절)"**로 정의하십시오.
3. 변화량이 **10도 미만**인 관절은 **"Stabilizers(안정화 관절)"**로 정의하십시오.
4. 분석은 오직 **Prime Movers**의 품질(Quality)에 집중해야 합니다.

### Step 2: Dynamic Pattern Recognition (동작 패턴 자동 감지)
운동 이름을 참고하지 말고, 다음 규칙에 따라 패턴을 스스로 분류하십시오:
- **Hip & Knee Flexion > 30°**: Lower Body Push (하체 미기)
- **Hip Flexion Only > 30°**: Hip Hinge (고관절 접기)
- **Elbow Flexion > 30°**: Upper Body Pull/Curl (상체 당기기)
- **Shoulder Pressing > 30°**: Upper Body Push (상체 밀기)
- **All Joints Static (< 10° change)**: Isometric Hold (버티기)

### Step 3: Pure Physics Calculation (순수 물리량 계산)
운동의 종류와 상관없이 다음 물리 법칙만으로 점수를 매기십시오:
- **Efficiency (효율성)**: 관절이 흔들리지 않고 궤적(Trajectory)이 매끄러운가? (Standard Deviation of Path)
- **Control (통제력)**: 신장성 수축(내려갈 때) 구간에서 속도가 급격히 빨라지지 않는가? (Gravity Control)
- **ROM (가동성)**: 해당 관절의 해부학적 한계(Anatomical Limit) 대비 몇 %를 사용했는가? (Not specific exercise limit)
`;
}

/**
 * 동적 로직 선택 가이드 (Data-First)
 */
function buildDynamicLogicSelection(
  context: WorkoutContext,
  visibleJoints: string[]
): string {
  return `
## 로직 선택 가이드 (Data-Driven)

**지침**: 사전 정의된 운동 타입("${context.exerciseName}")에 얽매이지 마십시오.
현재 감지된 **Prime Movers(주동 관절)**에 따라 적용할 로직을 스스로 결정하십시오.

1. **하체 관절(Hip, Knee)이 주동 관절일 때**:
   - 필수 로직: ROM_Check (가동범위), Symmetry (좌우대칭), Power_Output (폭발력)

2. **상체 관절(Shoulder, Elbow)이 주동 관절일 때**:
   - 필수 로직: ROM_Check (가동범위), Muscle_Isolation (고립도), Velocity_Consistency (속도 일정함)

3. **모든 관절이 정적(Static)일 때**:
   - 필수 로직: Stability (안정성), Muscle_Isolation (자세 유지력)

**현재 가시성 정보(Visible Joints)**: [${visibleJoints.join(", ")}]
- 이 목록에 없는 관절은 어떤 경우에도 분석하지 마십시오.
`;
}

/**
 * 생체역학 시스템 인스트럭션
 */
function buildBiomechanicsSystemInstruction(): string {
  return `
## 시스템 인스트럭션 (절대 규칙)

### 핵심 원칙: 보이는 것만 분석한다 (Zero Assumption)
1. **No Hallucination**: JSON 데이터에 좌표가 없거나 visible_joints에 없는 관절은 점수 계산에서 **제외(null)**하십시오.
2. **Context Independence**: "스쿼트니까 무릎이 보여야 해"라는 가정을 버리십시오. 무릎이 안 보이면 무릎 점수는 null이고, 보이는 어깨만 분석하면 됩니다.

### 분석 3단계 (The 3-Step Law)
**STEP 1: Measure Δ (Delta)**
- 각 관절의 Max - Min 각도 차이를 계산합니다.

**STEP 2: Classify Role**
- Δ > 20°: **Dynamic Component** (점수 비중 80%)
- Δ < 10°: **Static Component** (점수 비중 20%)

**STEP 3: Score based on Role**
- Dynamic Component는 **ROM과 속도** 위주로 평가합니다.
- Static Component는 **흔들림(Stability)** 위주로 평가합니다.
`;
}

/**
 * Context에 따라 선택할 로직 결정
 */
function selectLogicsForContext(
  bodyPart: string,
  contraction: string
): BiomechanicsLogic[] {
  const key = bodyPart + "_" + contraction;

  const logicMap: Record<string, BiomechanicsLogic[]> = {
    UpperBody_Isotonic: [
      "ROM_Check",
      "Muscle_Isolation",
      "Velocity_Consistency",
    ],
    UpperBody_Isometric: ["Stability", "Muscle_Isolation"],
    UpperBody_Isokinetic: ["Velocity_Consistency", "Symmetry"],
    LowerBody_Isotonic: ["ROM_Check", "Symmetry", "Power_Output"],
    LowerBody_Isometric: ["Stability", "Muscle_Isolation"],
    LowerBody_Isokinetic: ["Velocity_Consistency", "Symmetry"],
    FullBody_Isotonic: ["ROM_Check", "Symmetry", "Velocity_Consistency"],
    FullBody_Isometric: ["Stability", "Muscle_Isolation"],
    FullBody_Isokinetic: ["Velocity_Consistency", "Symmetry", "Power_Output"],
  };

  return logicMap[key] || ["ROM_Check", "Stability"];
}

/**
 * 엄격한 점수 기준표 (Scoring Rubric - Pure Bio-mechanics)
 */
function buildScoringRubric(): string {
  return `
## SCORING RUBRIC (PURE BIO-MECHANICS)
Use strict numeric thresholds. Do NOT care about the "Expected Exercise Form".

### 1. ROM Score (Anatomical Capacity)
**Criterion**: How much of the **human joint's capability** was used?
- **100 pts**: Joint moved > 80% of its anatomical limit (e.g., Knee bends fully).
- **70 pts**: Joint moved > 50% of limit.
- **30 pts**: Minimal movement (< 20% of limit) IF it was identified as a Prime Mover.

### 2. Stability Score (Motor Control)
**Criterion**: How stable are the non-moving parts?
- **100 pts**: Static joints deviation < 3 degrees.
- **50 pts**: Static joints deviation > 10 degrees (Shaking).

### 3. Tempo Score (Control)
**Criterion**: Is the movement controlled against gravity?
- **100 pts**: Eccentric (lowering) phase is slower than Concentric (lifting).
- **50 pts**: Drop / Free-fall detected (Gravity won).

### 4. Symmetry Score (Balance)
**Criterion**: Left vs Right Delta comparison.
- **100 pts**: Difference < 5%.
- **0 pts**: Only one side moved (unless intended unilateral).
`;
}

/**
 * 로직 정의 (변동 없음, 정의만 포함)
 */
function buildLogicDefinitions(): string {
  return `
## Logic Definitions
- **ROM_Check**: Angle Delta analysis.
- **Stability**: Jitter/Variance analysis.
- **Velocity_Consistency**: Speed variance.
- **Symmetry**: L/R Comparison.
- **Power_Output**: Acceleration analysis.
- **Muscle_Isolation**: Ratio of Target vs Non-Target movement.
`;
}

/**
 * 메인 프롬프트 생성 함수
 */
export function buildContextAwarePrompt(
  context: WorkoutContext,
  motionData: MotionData
): string {
  const dataDrivenInstruction = buildDataDrivenInstruction(context);
  const systemInstruction = buildBiomechanicsSystemInstruction();
  const scoringRubric = buildScoringRubric();
  const logicDefinitions = buildLogicDefinitions();
  const visibleJoints = motionData.visible_joints || [];
  const dynamicLogicSelection = buildDynamicLogicSelection(
    context,
    visibleJoints
  );

  // MediaPipe 데이터 변환 (토큰 절약을 위해 30프레임 샘플링)
  const sampledFrames = motionData.frames.slice(0, 30);
  const mediaPipeContext = JSON.stringify(
    {
      totalFrames: motionData.frames.length,
      sampledFrames: sampledFrames,
      visible_joints: visibleJoints,
    },
    null,
    2
  );

  return `
${dataDrivenInstruction}

${systemInstruction}

${scoringRubric}

${logicDefinitions}

${dynamicLogicSelection}

---
[GROUND TRUTH DATA]
⚠️ Analyze based ONLY on this data. Ignore the exercise label provided by the user if it conflicts with the data.

MediaPipe Data:
${mediaPipeContext}

**Final Output Rules:**
1. **motion_type**: Determine strictly by angle changes (isotonic > 15deg delta).
2. **detected_faults**: Return ["insufficient_rom", "instability", "asymmetry"] purely based on physics.
3. **overall_score**: Calculate based on the "Quality of Movement" of whatever body part moved the most.
4. **Return ONLY valid JSON.**
\`\`\`json
{
  "motion_type": "isotonic" | "isometric" | "unknown",
  "overall_score": number,
  "core_metrics": {
    "rom_score": number | null,
    "stability_score": number | null,
    "tempo_score": number | null,
    "symmetry_score": number | null,
    "posture_score": number | null,
    "intensity_score": number | null
  },
  "detected_faults": string[],
  "detailed_muscle_usage": {
    "muscle_name": number | null
  },
  "rom_data": {
    "joint_name": number | null
  }
}
\`\`\`
`;
}
