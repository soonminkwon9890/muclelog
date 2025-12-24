# MuscleLog 설정 가이드

## 완료된 작업

1. ✅ Supabase 데이터베이스 스키마 생성 (`supabase/schema.sql`)
2. ✅ 패키지 의존성 추가 (supabase_flutter, camera, google_mlkit_pose_detection 등)
3. ✅ 환경 변수 설정 (lib/config/env.dart)
4. ✅ Supabase 서비스 초기화 (lib/services/supabase_service.dart)
5. ✅ 로그인 화면 구현 (lib/screens/auth/login_screen.dart)
6. ✅ 세션 관리 및 라우팅 (lib/main.dart)
7. ✅ 카메라 화면 구현 (lib/screens/camera/camera_screen.dart)
8. ✅ 영상 업로드 및 분석 연동
9. ✅ 결과 표시 및 히스토리 기능

## 설정 필요 사항

### 1. .env 파일 설정

프로젝트 루트에 `.env` 파일을 생성하고 다음 내용을 추가하세요:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

### 2. Supabase 데이터베이스 설정

1. Supabase 대시보드에 접속
2. SQL Editor에서 `supabase/schema.sql` 파일의 내용을 실행
3. Storage에서 `videos` 버킷 생성 (비공개, 100MB 제한 권장)

### 3. 소셜 로그인 설정

#### 구글 로그인

1. Supabase 대시보드 > Authentication > Providers > Google
2. Google Cloud Console에서 OAuth 클라이언트 ID 생성
3. Supabase에 클라이언트 ID와 Secret 입력

#### 카카오 로그인

1. Supabase 대시보드 > Authentication > Providers > Kakao
2. Kakao Developers에서 앱 등록 및 REST API 키 발급
3. Supabase에 REST API 키 입력
4. Redirect URL 설정: `https://your-project.supabase.co/auth/v1/callback`

### 4. Android 설정 (소셜 로그인용)

`android/app/src/main/AndroidManifest.xml`에 다음을 추가:

```xml
<activity
    android:name="com.supabase.flutterquickstart.MainActivity"
    android:exported="true"
    android:launchMode="singleTop">
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    <!-- 소셜 로그인 리다이렉트 -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW"/>
        <category android:name="android.intent.category.DEFAULT"/>
        <category android:name="android.intent.category.BROWSABLE"/>
        <data android:scheme="com.example.flutter_application_1"/>
    </intent-filter>
</activity>
```

### 5. iOS 설정 (소셜 로그인용)

`ios/Runner/Info.plist`에 다음을 추가:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.example.flutter_application_1</string>
        </array>
    </dict>
</array>
```

## 테스트 방법

1. 앱 실행: `flutter run`
2. 이메일/비밀번호로 회원가입 테스트
3. 로그인 후 카메라 화면 표시 확인
4. 영상 촬영/선택 기능 테스트
5. 분석 결과 확인
6. 기록 조회 기능 테스트
7. 앱 재시작 시 세션 유지 확인

## 기술 스택

- **Flutter**: 3.10.3+
- **Gradle**: 8.13
- **Supabase**: Auth, Database, Storage
- **Google ML Kit**: Pose Detection
- **Camera**: 영상 촬영
