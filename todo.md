# MuscleLog 개발 체크리스트

## 1단계: 인프라 및 인증 시스템 구축 ✅

- [x] 1.1 Supabase 데이터베이스 스키마 SQL 파일 생성
- [x] 1.2 pubspec.yaml에 supabase_flutter 패키지 추가 및 flutter pub get 실행
- [x] 1.3 환경 변수 로드 유틸리티 (lib/config/env.dart) 생성 및 .env 파일 로드 설정
- [x] 1.4 Supabase 서비스 초기화 (lib/services/supabase_service.dart) 생성 및 세션 관리 구현
- [x] 1.5 로그인 화면 구현 (이메일, 구글, 카카오 소셜 로그인)
- [x] 1.6 main.dart 수정: 세션 확인, 로그인 상태별 라우팅, 리다이렉트 로직 구현
- [x] 1.7 메인 화면 기본 구조 생성 (임시 대시보드)
- [x] 1.8 1단계 기능 테스트 및 검증 (로그인 플로우, 세션 유지, 리다이렉트)

## 2단계: 카메라 화면 구현 ✅

- [x] 2.1 카메라 권한 처리
- [x] 2.2 MediaPipe 카메라 화면 구현
- [x] 2.3 메인 화면 통합

## 3단계: 영상 업로드 및 분석 연동 ✅

- [x] 3.1 영상 선택/촬영 기능
- [x] 3.2 Supabase Storage 업로드
- [x] 3.3 운동 설정 화면
- [x] 3.4 AI 서버 연동 준비

## 4단계: 결과 표시 및 히스토리 ✅

- [x] 4.1 분석 결과 오버레이
- [x] 4.2 기록 저장 및 조회

## 5단계: PRD User Flow 누락 화면 구현 ✅

- [x] 5.1 스플래시 화면 구현 (lib/screens/splash/splash_screen.dart)
- [x] 5.2 메인 대시보드 구현 (lib/screens/dashboard/dashboard_screen.dart)
  - [x] 최근 기록 미리보기 (3-5개)
  - [x] 플로팅 액션 버튼 (+) 구현
  - [x] 갤러리/카메라 선택 기능
  - [x] 기록 보기 네비게이션
- [x] 5.3 비교하기 기능 구현 (lib/screens/history/comparison_screen.dart)
  - [x] 두 개의 기록 선택 UI
  - [x] 비교 결과 다이얼로그
  - [x] history_screen에 비교하기 버튼 추가
- [x] 5.4 main.dart 라우팅 수정
  - [x] 스플래시 화면을 초기 화면으로 설정
  - [x] 로그인 후 대시보드로 이동하도록 변경
