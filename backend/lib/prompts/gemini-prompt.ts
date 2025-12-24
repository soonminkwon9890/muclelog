import type {
  WorkoutContext,
  MotionData,
  BiomechanicsLogic,
} from "../types/biomechanics";

/**
 * Gemini 프롬프트 생성 함수
 * Context-Aware Logic Selection 및 평가 가이드라인 포함
 */

/**
 * 데이터 기반 분석 원칙 (Fact Over Label)
 */
function buildDataDrivenInstruction(context: WorkoutContext): string {
  return `
## 데이터 기반 분석 원칙 (CRITICAL)

### 규칙 0: Fact Over Label
- 운동 이름("${context.exerciseName}")을 **참고만** 하되, 실제 motionData의 좌표 변화를 우선하세요.
- 사용자가 "스쿼트"를 선택했어도 실제 데이터가 상체 움직임만 있다면 상체 기준으로 분석하세요.
- **절대로** 운동 이름에 의존하여 점수를 추정하지 마세요. 오직 좌표 데이터만 사용하세요.

### Step 1: Active Joint Detection (활성 관절 감지)
1. 전체 motionData를 스캔하여 각 관절의 ROM(각도 변화량)을 계산하세요.
2. ROM > 15도인 관절만 "Active Joints"로 식별하세요.
3. ROM < 15도인 관절은 "Ignored Joints"로 분류하고 점수를 null로 설정하세요.
4. visible_joints 목록에 없는 관절은 무조건 "Ignored Joints"에 포함하세요.

### Step 2: Movement Pattern Recognition (움직임 패턴 인식)
활성 관절의 움직임 벡터를 보고 실제 운동 패턴을 정의하세요:
- "고관절 + 무릎 동시 굴곡/신전" → "Lower Body Push Pattern (Knee & Hip Dominant)"
- "팔꿈치 굴곡/신전" → "Upper Body Pull/Push Pattern"
- "대부분 관절 정적 유지" → "Isometric Hold Pattern"
- "어깨 + 팔꿈치 동시 움직임" → "Upper Body Compound Pattern"

### Step 3: Physics Calculation (물리량 계산)
- **ROM**: Max Angle - Min Angle (도 단위, 실제 측정값)
- **Stability**: 각도 변화의 표준편차 (낮을수록 안정적)
- **Velocity**: 각속도 (deg/s, 프레임 간 각도 변화 / 시간)
- **Tempo**: 단축/신장성 구간 시간 비율

### Step 4: Anatomy Mapping (해부학적 매핑)
- 관절 점수를 먼저 계산한 후, 해당 관절을 담당하는 근육에 점수를 부여하세요.
- 예: "무릎 ROM 점수 85점" → "대퇴사두근 점수 82점" (관절 점수 기반, 약간 낮게)
- 예: "고관절 기여도 90점" → "대둔근 점수 88점" (의존성 명시)
- **중요**: 관절이 움직이지 않았다면 해당 근육 점수도 null이어야 합니다.
`;
}

/**
 * 동적 로직 선택 가이드
 */
function buildDynamicLogicSelection(
  context: WorkoutContext,
  visibleJoints: string[]
): string {
  return `
## 동적 로직 선택 가이드

**중요**: 운동 이름("${context.exerciseName}")이 아닌 실제 motionData를 기반으로 로직을 선택하세요.

1. **활성 관절 감지 후 로직 선택**:
   - 활성 관절이 하체 중심 (hip, knee, ankle) → ROM_Check, Symmetry, Power_Output
   - 활성 관절이 상체 중심 (shoulder, elbow) → ROM_Check, Muscle_Isolation, Velocity_Consistency
   - 대부분 관절 정적 (ROM < 10도) → Stability, Muscle_Isolation
   - 혼합 패턴 (상체 + 하체) → ROM_Check, Symmetry, Velocity_Consistency

2. **패턴 기반 가중치**:
   - 동적 움직임 감지 (반복적 ROM 변화) → ROM_Check, Velocity_Consistency 가중치 높음
   - 정적 유지 감지 (ROM < 10도) → Stability, Muscle_Isolation 가중치 높음
   - 대칭 운동 (좌우 동시) → Symmetry 가중치 높음

3. **현재 visible_joints**: [${visibleJoints.join(", ")}]
   - 위 목록에 없는 관절은 분석하지 마세요.
`;
}

/**
 * 생체역학 시스템 인스트럭션 (기본 원칙)
 * Flutter의 _buildBiomechanicsSystemInstruction() 내용을 기반으로 작성
 */
function buildBiomechanicsSystemInstruction(): string {
  return `
## 생체역학 분석 원칙 (절대 규칙)

### 규칙 0: 보이는 관절만 분석 (AI Hallucination 방지) ⚠️ CRITICAL
**절대 규칙**: 입력된 JSON 데이터에 좌표가 없거나 `visible_joints` 목록에 없는 관절은 **절대로 분석하지 마라.**

1. **가시성 검증**:
   - Motion Data의 `visible_joints` 배열에 명시된 관절만 분석 대상으로 사용
   - 예: `visible_joints: ["shoulder", "elbow"]`인 경우, `knee`나 `ankle`은 **절대 분석하지 않음**

2. **보이지 않는 관절 처리**:
   - `visible_joints`에 없는 관절의 점수나 각도는 **반드시 `null`을 반환** (문자열 "N/A" 사용 금지)
   - 데이터가 없으면 반드시 `null` 사용 (타입 안전성)
   - **절대로** `"N/A"` 문자열을 사용하지 마세요. TypeScript 타입은 `number | null`만 허용합니다.

3. **핵심 관절 누락 시 처리**:
   - 사용자가 선택한 운동(예: 스쿼트)의 핵심 관절(무릎)이 `visible_joints`에 없다면:
     - 점수 대신 `null` 반환
     - `detected_faults` 배열에 "insufficient_visibility" 추가
     - **절대로** 텍스트 피드백 메시지를 생성하지 마세요 (의료법 리스크 방지)

4. **좌표 데이터 검증**:
   - 각 프레임의 `landmarks` 배열에서 `likelihood < 0.5`인 관절은 즉시 DISCARD
   - 추가로 `visible_joints` 목록과 일치하지 않는 관절은 **절대 계산에 사용하지 않음**
   - **Zero Assumption**: 보이지 않는 관절의 위치나 근육 활성도를 추정하지 마세요

5. **Visibility 임계값**:
   - MediaPipe `likelihood` < 0.5인 관절은 즉시 제외
   - Flutter에서 이미 0.6으로 필터링했지만, 백엔드에서도 0.5 기준으로 재검증

**예시**:
- 입력: `visible_joints: ["shoulder", "elbow"]`, 운동: "스쿼트"
- 올바른 처리: `knee` 점수 = `null`, `ankle` 점수 = `null`, `detected_faults: ["insufficient_visibility"]`
- 잘못된 처리: `knee` 점수를 추정하여 숫자로 반환 (❌ 금지), `"N/A"` 문자열 사용 (❌ 금지)

### 규칙 A: 위치 이동 vs 관절 가동 구분
MUST distinguish between 'Spatial Translation' and 'Joint Articulation'.

- **Spatial Translation (공간 이동)**: 몸통이나 팔이 통째로 움직이는 것
  - 예: 스쿼트 시 등, 숄더 프레스 시 손목
  - 이것만으로는 주동근(Prime Mover)이 아님

- **Joint Articulation (관절 가동)**: 관절의 각도가 실제로 줄어들거나 늘어나는 것
  - 예: 스쿼트 시 무릎, 숄더 프레스 시 팔꿈치
  - 이것이 주동근(Prime Mover)임

### 규칙 B: 안정근 vs 주동근 구분
- **STABILIZER (안정근)**: 
  - 신체 부위가 공간에서 이동하지만 관절 각도가 정적으로 유지됨
  - 예: 숄더 프레스에서 손목(Wrist), 스쿼트에서 척추(Spine)
  - 점수: 10-20% (시각적 움직임이 크더라도)

- **PRIME_MOVER (주동근)**:
  - 관절 각도가 크게 변화함 (굴곡/신전)
  - 예: 숄더 프레스에서 어깨(Shoulder), 스쿼트에서 무릎(Knee)
  - 점수: 높게 책정 (60-90%)

### 규칙 C: 점수 기준
- STABILIZERs must have significantly lower usage scores (10-20%) compared to PRIME_MOVERs, even if visual movement is large.
- Do not assume high velocity equals high activation. Focus on the Range of Motion (ROM) of the joint itself.

### 규칙 D: 분석 3단계 법칙 (CORE BIOMECHANICS LOGIC)
You must analyze the movement in 3 steps for EVERY body part:

**STEP 1: Calculate Angle Delta (Δ)**
- Estimate the change in joint angle during the movement (Max Angle - Min Angle).
- Do NOT judge based on spatial distance (how many pixels it moved).
- Consider the joint's range of motion (ROM) throughout the entire exercise.

**STEP 2: Apply the 'Static vs Dynamic' Rule**
- **IF Angle Delta < 20 degrees:** The joint is **STATIC** (Isometric). It is acting as a **STABILIZER**.
- **IF Angle Delta >= 20 degrees:** The joint is **DYNAMIC** (Isotonic). It is acting as a **PRIME_MOVER**.

**STEP 3: Assign Score & Role**
- **STABILIZER (Angle Delta < 20 degrees):**
  - MUST be assigned a low score (under 20%), even if it moved significantly in space.
  - Example: Wrist in Shoulder Press (moves up/down but angle stays ~180 degrees) → score: 10-15%
- **PRIME_MOVER (Angle Delta >= 20 degrees):**
  - Assign a high score based on the range of motion.
  - Example: Shoulder in Shoulder Press (flexion from ~0 to ~180 degrees) → score: 60-90%

### 규칙 E: 운동 유형 자동 감지 및 맞춤형 분석 (ADVANCED MOVEMENT CLASSIFICATION)
You must first classify the exercise type into one of two categories:

**TYPE A: DYNAMIC MOVEMENT (Isotonic)**
- **Condition:** Significant repetitive changes in joint angles throughout the video (e.g., Squat, Shoulder Press, Bicep Curl).
- **Detection:** Look for repetitive patterns of joint angle changes (>20° variations).
- **Scoring Rule:** Apply the **"Angle Delta Rule"** (규칙 D의 3단계 법칙).
  - Joints with large angle changes (>=20°) are PRIME MOVERS.
  - Joints that stay still (<20°) are STABILIZERS.

**TYPE B: STATIC HOLD (Isometric)**
- **Condition:** The user maintains a fixed posture for the majority of the video (e.g., Plank, Wall Sit, Hollow Body Hold, Bridge Hold).
- **Detection:** Look for minimal joint angle changes (<10° overall) but sustained muscle activation.
- **Scoring Rule:** Apply the **"Anti-Gravity Rule"**.
  - Identify body parts that are fighting against gravity to maintain the pose.
  - **EXCEPTION:** Even if the Angle Delta is 0, if the muscle is preventing collapse against gravity, classify it as a **PRIME_MOVER** with a **HIGH SCORE**.
  - Example (Plank):
    - Spine/Hips: Angle Delta ≈ 0°, but Core/Abs prevent hips from sagging → **Core (Spine) is PRIME_MOVER, score: 60-80%**
    - Shoulders: Angle Delta ≈ 0°, but Deltoids prevent collapse → **Shoulders are PRIME_MOVER, score: 50-70%**
    - Wrist/Elbow: Static support → **STABILIZER, score: 10-15%**
  - Example (Wall Sit):
    - Knees: Angle Delta ≈ 0°, but Quads prevent sliding down → **Knees (Quads) are PRIME_MOVER, score: 70-90%**
    - Hips: Static support → **STABILIZER, score: 10-20%**

**Decision Flow:**
1. Analyze the overall movement pattern in the video.
2. If most joints show <10° angle changes → Classify as **STATIC HOLD**.
3. If joints show repetitive >20° angle changes → Classify as **DYNAMIC MOVEMENT**.
4. Apply the appropriate scoring rule based on the classification.
`;
}

/**
 * Context에 따라 선택할 로직 결정
 */
function selectLogicsForContext(
  bodyPart: string,
  contraction: string
): BiomechanicsLogic[] {
  const key = `${bodyPart}_${contraction}`;

  const logicMap: Record<string, BiomechanicsLogic[]> = {
    UpperBody_Isotonic: ["ROM_Check", "Muscle_Isolation", "Velocity_Consistency"],
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
 * 엄격한 점수 기준표 (Scoring Rubric)
 * Phase 2: 6-Core Biomechanical Logic의 정확한 점수 계산 기준
 */
function buildScoringRubric(): string {
  return `
## PHASE 2: SCORING THRESHOLDS (THE RUBRIC)
Use these strict numeric thresholds to calculate scores. Do NOT estimate or use arbitrary values.

### 1. ROM Score (Target vs Observed)
Calculate: (Observed_ROM / Ideal_ROM) * 100

**Scoring Thresholds:**
- **100 pts:** Angle change > 85% of anatomical max (e.g., Knee flexion > 110°)
- **80 pts:** Angle change > 70% (Functional range, e.g., Knee ~90°)
- **< 50 pts:** Angle change < 50% (Partial rep)

**Calculation Method:**
1. Measure actual ROM from MediaPipe coordinates: Max Angle - Min Angle
2. Compare against anatomical maximum for that joint
3. Apply threshold above to assign score

### 2. Stability Score (Jitter Analysis)
Calculate: Variance of coordinates for non-moving parts

**Scoring Thresholds:**
- **100 pts:** Non-moving joints deviate < 3 degrees
- **80 pts:** Deviation 3-8 degrees
- **< 60 pts:** Deviation > 10 degrees (Severe instability)

**Calculation Method:**
1. Identify non-moving joints (ROM < 10 degrees)
2. Calculate standard deviation of angle changes
3. Apply threshold above to assign score

### 3. Tempo Score (Gravity Control)
Calculate: Duration of Eccentric phase (lengthening)

**Scoring Thresholds:**
- **100 pts:** Eccentric phase (lengthening) duration > 1.5 sec
- **50 pts:** Eccentric phase < 0.5 sec (Drop/Free-fall)
- **Note:** Explosive concentric phase is allowed and good

**Calculation Method:**
1. Distinguish Concentric (speed up) vs Eccentric (slow down) phases based on angular velocity
2. Measure Eccentric phase duration from MediaPipe frame timestamps
3. Apply threshold above to assign score

### 4. Symmetry Score (Left vs Right Balance)
Calculate: Compare ROM and Velocity between Left/Right sides

**Scoring Thresholds:**
- **100 pts:** Difference between L/R < 5%
- **80 pts:** Difference 5-15%
- **< 60 pts:** Difference > 15% (Significant imbalance)

**Condition:** Only applies if BOTH left and right limbs are visible in visible_joints array
**If condition not met:** Return null (NOT "N/A")

**Calculation Method:**
1. Check if both left and right limbs are in visible_joints
2. If not, return null
3. If yes, calculate ROM and Velocity for each side
4. Calculate percentage difference: |Left - Right| / ((Left + Right) / 2) * 100
5. Apply threshold above to assign score

### 5. Posture Score (Alignment)
Calculate: Biomechanical faults detection

**Scoring Thresholds:**
- **100 pts:** Spine flexion/extension varies < 5 degrees from neutral
- **< 50 pts:** Spine rounds or arches > 15 degrees under load
- **< 50 pts:** Knee valgus (inward collapse) > 10 degrees

**Calculation Method:**
1. Use vector analysis between Hip-Shoulder-Ear (Spine Line)
2. Measure deviation from neutral position
3. Check for Knee Valgus: Measure angle between knee and ankle alignment
4. Apply threshold above to assign score

### 6. Intensity Score (Load Factor)
Calculate: Score = (ROM_Score * Load_Type_Coefficient)

**Coefficients:**
- Vertical Movement against Gravity: 1.0
- Horizontal Movement: 0.6
- Momentum/Swing: 0.3

**Calculation Method:**
1. First calculate ROM_Score using rubric #1
2. Determine movement type from MediaPipe coordinate vectors
3. Apply appropriate coefficient
4. Final score = ROM_Score * Coefficient

**Important:** All scores must be calculated using MediaPipe coordinate data. Do NOT estimate or hallucinate values.
`;
}

/**
 * 6가지 로직 정의 및 평가 기준
 */
function buildLogicDefinitions(): string {
  return `
## 6가지 핵심 생체역학 로직 정의

### 1. ROM_Check (가동범위)
**목적**: 관절이 움직인 각도의 범위가 충분한가?
**평가 기준**:
- 각 관절의 최대 각도와 최소 각도의 차이(Δ)를 계산
- Δ >= 20도: 충분한 ROM (점수 60-90%)
- 10도 <= Δ < 20도: 보통 ROM (점수 40-60%)
- Δ < 10도: 부족한 ROM (점수 10-40%)
**주로 사용**: Isotonic 운동

### 2. Stability (안정성)
**목적**: 동작 중 흔들림(Jitter)이 없는가?
**평가 기준**:
- 프레임 간 각도 변화의 표준편차 계산
- 표준편차 < 5도: 매우 안정적 (점수 80-100%)
- 5도 <= 표준편차 < 10도: 안정적 (점수 60-80%)
- 표준편차 >= 10도: 불안정 (점수 20-60%)
**주로 사용**: Isometric 운동

### 3. Velocity_Consistency (속도 일관성)
**목적**: 반복 속도가 일정한가?
**평가 기준**:
- 각 반복 구간의 평균 속도 계산
- 속도 변동계수(CV) < 0.1: 매우 일관적 (점수 80-100%)
- 0.1 <= CV < 0.2: 일관적 (점수 60-80%)
- CV >= 0.2: 불일관적 (점수 20-60%)
**주로 사용**: Isotonic, Isokinetic 운동

### 4. Symmetry (좌우 대칭)
**목적**: 좌우 팔/다리의 움직임이 대칭적인가?
**평가 기준**:
- 좌우 대응 관절의 각도 차이 계산 (예: Left Shoulder vs Right Shoulder)
- 차이 < 10도: 매우 대칭적 (점수 80-100%)
- 10도 <= 차이 < 20도: 대칭적 (점수 60-80%)
- 차이 >= 20도: 비대칭적 (점수 20-60%)
**주로 사용**: 모든 운동 타입

### 5. Power_Output (순발력)
**목적**: 단위 시간당 움직임의 변화량이 폭발적인가?
**평가 기준**:
- 각속도 변화율(angular acceleration) 계산
- 가속도 > 50 deg/s²: 높은 순발력 (점수 70-100%)
- 20 deg/s² <= 가속도 <= 50 deg/s²: 보통 (점수 40-70%)
- 가속도 < 20 deg/s²: 낮은 순발력 (점수 10-40%)
**주로 사용**: Lower Body Isotonic, Full Body Isokinetic

### 6. Muscle_Isolation (고립도)
**목적**: 타겟 관절 외에 불필요한 관절 개입이 없는가?
**평가 기준**:
- 타겟 부위의 관절 각도 변화량 vs 비타겟 부위의 각도 변화량 비율 계산
- 비타겟 부위 변화량 < 타겟 부위의 20%: 높은 고립도 (점수 80-100%)
- 20% <= 비타겟 변화량 < 50%: 보통 고립도 (점수 50-80%)
- 비타겟 변화량 >= 50%: 낮은 고립도 (점수 20-50%)
**주로 사용**: Upper Body, Isometric 운동
`;
}

/**
 * Context-Aware 프롬프트 생성
 */
export function buildContextAwarePrompt(
  context: WorkoutContext,
  motionData: MotionData
): string {
  // 1. 시스템 인스트럭션 및 루브릭 준비
  const dataDrivenInstruction = buildDataDrivenInstruction(context);
  const systemInstruction = buildBiomechanicsSystemInstruction();
  const scoringRubric = buildScoringRubric(); // ⚠️ 새로운 Scoring Rubric 추가
  const logicDefinitions = buildLogicDefinitions();
  
  // 보이는 관절 목록 추출
  const visibleJoints = motionData.visible_joints || [];
  const dynamicLogicSelection = buildDynamicLogicSelection(context, visibleJoints);
  
  // 동적 로직 선택 (기존 정적 선택은 참고용으로만 사용)
  const selectedLogics = selectLogicsForContext(
    context.bodyPart,
    context.contraction
  );

  // 2. ⚠️ 핵심: MediaPipe 데이터를 JSON 문자열로 변환 (Gemini가 읽을 수 있게)
  // - motionData.frames: 프레임별 landmarks 배열
  // - motionData.visible_joints: 보이는 관절 목록
  // - 샘플링하여 토큰 수 제한 (최대 30프레임)
  const sampledFrames = motionData.frames.slice(0, 30);
  
  // ⚠️ 이 부분이 핵심! MediaPipe 데이터를 문자열로 변환
  const mediaPipeContext = JSON.stringify(
    {
      totalFrames: motionData.frames.length,
      sampledFrames: sampledFrames,
      visible_joints: visibleJoints,
    },
    null,
    2 // 들여쓰기로 가독성 향상
  );

  // 3. 프롬프트 조립 (MediaPipe 데이터를 명시적으로 주입)
  return `
${dataDrivenInstruction}

${systemInstruction}

${scoringRubric}

${logicDefinitions}

${dynamicLogicSelection}

---
[GROUND TRUTH DATA FROM MEDIAPIPE]
⚠️ CRITICAL: The following is the precise coordinate history extracted from the video.
You MUST use this data as your source of truth. Do NOT estimate or hallucinate.

MediaPipe Data:
${mediaPipeContext}

**Critical Rules:**
- Only analyze joints listed in visible_joints array
- Use exact coordinates from landmarks array (x, y, z, likelihood)
- Calculate angles and ROM from these exact coordinates
- If a joint is not in visible_joints, set its score to null (NOT "N/A")
- Calculate scores based on the rubric above using this real data
- Do NOT make up coordinates or angles that are not in this data
- If likelihood < 0.5 for any landmark, discard that joint immediately
---

Now, analyze based on the Rules and rubrics defined above.
Return the result in the following JSON format:

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

**CRITICAL OUTPUT RULES:**
1. **motion_type**: Determine based on ROM history
   - "isotonic": ROM history shows significant angle changes (> 15 degrees)
   - "isometric": ROM history shows minimal changes (< 10 degrees)
   - "unknown": Insufficient data

2. **overall_score**: Weighted average calculation
   - Formula: (ROM * 0.3) + (Stability * 0.3) + (Posture * 0.2) + (Tempo * 0.2)
   - If any score is null, exclude it and recalculate weights
   - Example: If ROM is null, use (Stability * 0.43) + (Posture * 0.29) + (Tempo * 0.29)

3. **core_metrics**: Use the Scoring Rubric above to calculate each score
   - Apply strict thresholds from the rubric
   - If data is insufficient or joint not visible, return null (NOT "N/A")
   - **NEVER use "N/A" string. Only use null or number.**

4. **detected_faults**: Array of fault codes (NO text feedback for safety)
   - Examples: ["knee_valgus", "uncontrolled_tempo", "insufficient_visibility"]
   - If no faults detected, return empty array []
   - **DO NOT generate text feedback messages (medical law risk prevention)**

5. **detailed_muscle_usage**: Muscle activation scores
   - Only include muscles for visible joints
   - Use null if muscle is not targeted or joint not visible
   - Values: 0.0-100.0 or null

6. **rom_data**: Joint ROM measurements in degrees
   - Only include joints from visible_joints array
   - Use null if joint not visible or not active
   - Values: degrees (number) or null

**ABSOLUTE PROHIBITIONS:**
- ❌ DO NOT use "N/A" string anywhere. Use null instead.
- ❌ DO NOT generate feedback_message or any text feedback (safety risk)
- ❌ DO NOT estimate or hallucinate coordinates not in MediaPipe data
- ❌ DO NOT analyze joints not in visible_joints array

**Return ONLY valid JSON. No markdown, no explanations, just the JSON object.**
`;
}
