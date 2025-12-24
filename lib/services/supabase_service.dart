import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

/// Supabase 서비스 클래스
/// Supabase 클라이언트 초기화 및 세션 관리를 담당합니다.
class SupabaseService {
  static SupabaseService? _instance;
  static SupabaseService get instance {
    _instance ??= SupabaseService._();
    return _instance!;
  }

  SupabaseService._();

  /// Supabase 클라이언트 초기화
  /// 앱 시작 시 main() 함수에서 호출해야 합니다.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // 딥링크에서 세션 자동 감지 활성화
        detectSessionInUri: true,
      ),
    );
  }

  /// Supabase 클라이언트 인스턴스
  SupabaseClient get client => Supabase.instance.client;

  /// 현재 사용자 세션
  Session? get currentSession => client.auth.currentSession;

  /// 현재 사용자
  User? get currentUser => client.auth.currentUser;

  /// 로그인 상태 확인
  bool get isLoggedIn => currentSession != null;

  /// OAuth 에러 처리 공통 함수
  /// OAuth 인증 중 발생한 에러를 사용자 친화적인 메시지로 변환합니다.
  String _handleOAuthError(dynamic error, String providerName) {
    final errorString = error.toString();
    final errorMessage = errorString.toLowerCase();

    debugPrint('🔴 OAuth 에러 분석: $errorString');

    if (errorMessage.contains('provider is not enabled')) {
      return '$providerName 로그인이 현재 비활성화되어 있습니다. 관리자에게 문의하세요.';
    } else if (errorMessage.contains('requested path is invalid')) {
      return '리디렉션 URL 설정이 잘못되었습니다. Supabase 대시보드에서 Redirect URLs를 확인해주세요.';
    } else if (errorMessage.contains('network') ||
        errorMessage.contains('connection')) {
      return '네트워크 연결을 확인해주세요.';
    } else if (errorMessage.contains('cancel')) {
      return '로그인이 취소되었습니다.';
    } else if (errorMessage.contains('invalid_request')) {
      return 'OAuth 요청이 잘못되었습니다. Google Cloud Console 설정을 확인해주세요.';
    } else {
      final truncatedError = errorString.length > 100
          ? '${errorString.substring(0, 100)}...'
          : errorString;
      return '$providerName 로그인에 실패했습니다: $truncatedError';
    }
  }

  /// 이메일/비밀번호로 로그인
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// 이메일/비밀번호로 회원가입
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? nickname,
    String? redirectTo,
  }) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: nickname != null ? {'nickname': nickname} : null,
      emailRedirectTo: redirectTo,
    );
  }

  /// 구글 소셜 로그인
  /// [forceAccountSelection]이 true이면 항상 계정 선택 화면을 표시합니다.
  Future<void> signInWithGoogle({bool forceAccountSelection = true}) async {
    try {
      debugPrint('🔵 구글 OAuth 시작');
      debugPrint('🔵 redirectTo: ${Env.deepLinkRedirectUrl}');
      debugPrint('🔵 forceAccountSelection: $forceAccountSelection');

      await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Env.deepLinkRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: forceAccountSelection
            ? {
                'prompt': 'select_account', // 계정 선택 화면 강제 표시
              }
            : null,
      );
      debugPrint('🟢 구글 OAuth 요청 완료');
    } catch (e, stackTrace) {
      debugPrint('🔴 구글 OAuth 오류: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      throw Exception(_handleOAuthError(e, '구글'));
    }
  }

  /// 카카오 소셜 로그인
  Future<void> signInWithKakao() async {
    try {
      debugPrint('🔵 카카오 OAuth 시작');
      debugPrint('🔵 redirectTo: ${Env.deepLinkRedirectUrl}');
      await client.auth.signInWithOAuth(
        OAuthProvider.kakao,
        redirectTo: Env.deepLinkRedirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      debugPrint('🟢 카카오 OAuth 요청 완료');
    } catch (e, stackTrace) {
      debugPrint('🔴 카카오 OAuth 오류: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      throw Exception(_handleOAuthError(e, '카카오'));
    }
  }

  /// 로그아웃
  /// [revokeTokens]가 true이면 OAuth 제공자(Google, Kakao 등)의 토큰도 함께 취소합니다.
  /// 이렇게 하면 다음 로그인 시 계정 선택 화면이 표시됩니다.
  Future<void> signOut({bool revokeTokens = false}) async {
    await client.auth.signOut(
      scope: revokeTokens ? SignOutScope.global : SignOutScope.local,
    );
    debugPrint('🟢 로그아웃 완료 (revokeTokens: $revokeTokens)');
  }

  /// 세션 상태 스트림 구독
  /// 로그인/로그아웃 상태 변경을 감지할 수 있습니다.
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  /// 분석 결과를 workout_logs 테이블에 저장
  /// [logId] 분석 로그 ID
  /// [analysisResult] 분석 결과 Map (agonist_avg_score, antagonist_avg_score, synergist_avg_score, consistency_score 등 포함)
  ///
  /// 예시:
  /// ```dart
  /// await SupabaseService.instance.updateAnalysisResult(
  ///   logId: 123,
  ///   analysisResult: {
  ///     'agonist_avg_score': 85.5,
  ///     'antagonist_avg_score': 10.2,
  ///     'synergist_avg_score': 4.3,
  ///     'consistency_score': 92.1,
  ///   },
  /// );
  /// ```
  Future<void> updateAnalysisResult({
    required String logId, // UUID String
    required Map<String, dynamic> analysisResult,
    String? status,
  }) async {
    try {
      final updateData = <String, dynamic>{'analysis_result': analysisResult};

      if (status != null) {
        updateData['status'] = status;
      }

      await client.from('workout_logs').update(updateData).eq('id', logId);

      debugPrint('🟢 분석 결과 저장 완료 (logId: $logId)');
    } catch (e) {
      debugPrint('🔴 분석 결과 저장 실패: $e');
      rethrow;
    }
  }

  /// 운동 이름 수정
  /// [logId] 분석 로그 ID
  /// [newName] 새로운 운동 이름
  Future<void> updateExerciseName({
    required String logId, // UUID String
    required String newName,
  }) async {
    try {
      await client
          .from('workout_logs')
          .update({'exercise_name': newName})
          .eq('id', logId);
      debugPrint('🟢 운동 이름 수정 완료 (logId: $logId, newName: $newName)');
    } catch (e) {
      debugPrint('🔴 운동 이름 수정 실패: $e');
      rethrow;
    }
  }

  /// 분석 기록 삭제
  /// [logId] 분석 로그 ID (UUID String)
  Future<void> deleteAnalysisLog(String logId) async {
    try {
      await client.from('workout_logs').delete().eq('id', logId);
      debugPrint('🟢 분석 기록 삭제 완료 (logId: $logId)');
    } catch (e) {
      debugPrint('🔴 분석 기록 삭제 실패: $e');
      rethrow;
    }
  }
}
