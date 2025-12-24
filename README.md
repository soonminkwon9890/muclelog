# MuscleLog

AI 동작 기반 근육 분석 리포트 앱

## 개요

MuscleLog는 운동 영상을 촬영하고 AI(MediaPipe)를 활용하여 근육 사용률을 분석하는 Flutter 앱입니다.

## 주요 기능

- 🔐 **인증 시스템**: 이메일, 구글, 카카오 소셜 로그인
- 📹 **실시간 포즈 감지**: MediaPipe를 활용한 실시간 포즈 추적
- 🎥 **영상 분석**: 운동 영상 업로드 및 AI 분석
- 📊 **결과 시각화**: 영상 위 오버레이로 분석 결과 표시
- 📝 **기록 관리**: 분석 기록 조회 및 비교

## 기술 스택

- **Frontend**: Flutter (Dart 3.10.3+)
- **Backend**: Supabase (Auth, Database, Storage)
- **AI**: Google ML Kit Pose Detection
- **Build**: Gradle 8.13

## 시작하기

### 필수 요구사항

- Flutter SDK 3.10.3 이상
- Dart SDK 3.10.3 이상
- Android Studio / Xcode (모바일 개발용)
- Supabase 계정

### 설치 및 실행

1. **저장소 클론**

   ```bash
   git clone <repository-url>
   cd flutter_application_1
   ```

2. **의존성 설치**

   ```bash
   flutter pub get
   ```

3. **환경 변수 설정**
   프로젝트 루트에 `.env` 파일 생성:

   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

4. **Supabase 설정**

   - `supabase/schema.sql` 파일을 Supabase SQL Editor에서 실행
   - Storage에 `videos` 버킷 생성 (비공개 권장)

5. **앱 실행**
   ```bash
   flutter run
   ```

## 프로젝트 구조

```
lib/
├── main.dart                    # 앱 진입점
├── config/
│   └── env.dart                # 환경 변수 관리
├── services/
│   ├── supabase_service.dart   # Supabase 서비스
│   └── storage_service.dart    # Storage 서비스
└── screens/
    ├── auth/                   # 인증 화면
    ├── camera/                 # 카메라 화면
    ├── exercise/               # 운동 설정 화면
    ├── loading/                # 로딩 화면
    ├── result/                 # 결과 화면
    └── history/                # 기록 조회 화면

supabase/
└── schema.sql                  # 데이터베이스 스키마
```

## 상세 설정

자세한 설정 방법은 [SETUP.md](SETUP.md)를 참고하세요.

## 라이선스

이 프로젝트는 개인 프로젝트입니다.vercel 배

