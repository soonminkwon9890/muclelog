# Next.js Gemini Biomechanics Engine

Flutter 앱에서 수집한 Motion Data를 Gemini API로 분석하여 Supabase에 저장하는 백엔드 시스템입니다.

## 프로젝트 구조

```
backend/
├── app/
│   ├── api/
│   │   └── analyze-workout/
│   │       └── route.ts          # HTTP POST API Route
│   └── actions/
│       └── analyze-workout.ts   # Server Action (내부 로직)
├── lib/
│   ├── types/
│   │   └── biomechanics.ts      # TypeScript 인터페이스
│   ├── prompts/
│   │   └── gemini-prompt.ts     # Gemini 프롬프트 생성
│   └── supabase/
│       └── client.ts            # Supabase 클라이언트
├── .env.local                    # 환경 변수 (Git에 커밋 금지)
└── package.json
```

## 설치 및 실행

### 1. 의존성 설치

```bash
cd backend
npm install
```

### 2. 환경 변수 설정

`.env.local.example` 파일을 `.env.local`로 복사하고 실제 값 입력:

```bash
cp .env.local.example .env.local
```

필수 환경 변수:
- `GEMINI_API_KEY`: Google Gemini API 키
- `NEXT_PUBLIC_SUPABASE_URL`: Supabase 프로젝트 URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: Supabase Anon Key
- `SUPABASE_SERVICE_ROLE_KEY`: Supabase Service Role Key

### 3. 개발 서버 실행

```bash
npm run dev
```

서버는 `http://localhost:3000`에서 실행됩니다.

## API 엔드포인트

### POST /api/analyze-workout

운동 분석을 수행합니다.

**Request Body:**
```json
{
  "context": {
    "bodyPart": "UpperBody" | "LowerBody" | "FullBody",
    "contraction": "Isotonic" | "Isometric" | "Isokinetic",
    "exerciseName": "스쿼트"
  },
  "motionData": {
    "frames": [
      {
        "timestamp": 0.0,
        "landmarks": [
          {
            "type": "nose",
            "x": 0.5,
            "y": 0.3,
            "z": 0.0,
            "likelihood": 0.9
          }
        ]
      }
    ]
  },
  "userId": "user-uuid",
  "logId": "log-id"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "applied_logics": ["ROM_Check", "Symmetry"],
    "scores": {
      "overall_score": 85.5,
      "rom_score": 90.0,
      "stability_score": null,
      "velocity_score": 80.0,
      "symmetry_score": 88.0,
      "power_score": null,
      "isolation_score": null
    },
    "feedback": {
      "summary": "전반적으로 우수한 수행",
      "details": "..."
    }
  }
}
```

## Supabase 스키마 수정

`analysis_logs` 테이블에 `ai_analysis_result` 컬럼을 추가해야 합니다:

```sql
ALTER TABLE public.analysis_logs 
ADD COLUMN IF NOT EXISTS ai_analysis_result JSONB;
```

마이그레이션 스크립트: `supabase/migrations/add_ai_analysis_result.sql`

## 주요 기능

1. **Context-Aware Logic Selection**: Body Part와 Contraction Type에 따라 6가지 로직 중 2-3개 자동 선택
2. **Gemini AI 분석**: 선택된 로직에 대해 0-100 점수 계산
3. **Supabase 저장**: 분석 결과를 `ai_analysis_result` 컬럼에 JSONB 형식으로 저장
4. **에러 처리**: 재시도 로직 및 Fallback 결과 제공

## 개발 참고사항

- TypeScript strict mode 사용
- Server Actions는 "use server" 디렉티브 필수
- CORS 설정은 `next.config.js`에 포함됨
- 환경 변수는 `.env.local`에 저장 (Git 커밋 금지)
