import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경 변수 관리 클래스
/// .env 파일에서 필요한 설정값을 로드하고 제공합니다.
class Env {
  /// .env 파일 초기화
  /// 앱 시작 시 main() 함수에서 호출해야 합니다.
  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
  }

  /// Supabase 프로젝트 URL
  static String get supabaseUrl {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception('SUPABASE_URL이 .env 파일에 설정되지 않았습니다.');
    }
    return url;
  }

  /// Supabase Anon Key
  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY가 .env 파일에 설정되지 않았습니다.');
    }
    return key;
  }

  /// Supabase Service Role Key
  /// ⚠️ 주의: Service Role Key는 매우 강력한 권한을 가지므로
  /// 클라이언트 사이드에 노출되지 않도록 주의해야 합니다.
  /// 가능하면 서버 사이드에서만 사용하는 것을 권장합니다.
  static String get supabaseServiceRoleKey {
    final key = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('SUPABASE_SERVICE_ROLE_KEY가 .env 파일에 설정되지 않았습니다.');
    }
    return key;
  }

  /// 카카오 클라이언트 ID (선택사항)
  static String? get kakaoClientId => dotenv.env['KAKAO_CLIENT_ID'];

  /// 구글 클라이언트 ID (선택사항)
  static String? get googleClientId => dotenv.env['GOOGLE_CLIENT_ID'];

  /// Gemini API Key
  static String get geminiApiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GEMINI_API_KEY가 .env 파일에 설정되지 않았습니다.');
    }
    return key;
  }

  /// OAuth 리디렉션을 위한 Deep Link URL
  /// Supabase OAuth 인증 후 앱으로 돌아오기 위한 커스텀 스킴 URL입니다.
  /// ⚠️ 주의: Supabase Redirect URLs와 정확히 일치해야 합니다 (슬래시 없음)
  static const String deepLinkRedirectUrl =
      'com.myfitness.app://login-callback';

  /// Next.js API Base URL
  /// Gemini Workout Analysis 백엔드 서버 URL
  static String get nextJsApiUrl {
    final url = dotenv.env['NEXT_JS_API_URL'];
    if (url == null || url.isEmpty) {
      // 기본값: Vercel 배포 환경
      return 'https://muclelog.vercel.app';
    }
    return url;
  }
}
