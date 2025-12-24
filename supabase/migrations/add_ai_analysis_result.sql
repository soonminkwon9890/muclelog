-- ============================================
-- 마이그레이션: ai_analysis_result 컬럼 추가
-- ============================================
-- Next.js Gemini 생체역학 엔진의 분석 결과를 저장하기 위한 컬럼 추가

ALTER TABLE public.analysis_logs 
ADD COLUMN IF NOT EXISTS ai_analysis_result JSONB;

-- 컬럼 설명 추가
COMMENT ON COLUMN public.analysis_logs.ai_analysis_result IS 
'Gemini AI가 계산한 생체역학 분석 결과. 6가지 로직 중 선택된 로직의 점수와 피드백을 포함합니다.';
