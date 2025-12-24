import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../../services/supabase_service.dart';
import '../auth/login_screen.dart';
import '../dashboard/dashboard_screen.dart';

/// 스플래시 화면
/// 앱 시작 시 로고를 표시하고 로그인 상태를 확인하여 적절한 화면으로 이동합니다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _navigateToNextScreen();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// 딥링크 초기화 및 리스너 설정
  /// OAuth 콜백을 처리하기 위해 필요합니다.
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // 앱이 딥링크로 시작된 경우 처리
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('Splash: Initial deep link: $initialUri');
        await _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Splash: 딥링크 초기화 오류: $e');
    }

    // 앱이 실행 중일 때 딥링크 수신
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      debugPrint('Splash: Received deep link: $uri');
      await _handleDeepLink(uri);
    });
  }

  /// 딥링크 처리 함수
  /// OAuth 콜백에서 받은 딥링크를 처리하고 Supabase 세션을 확인합니다.
  Future<void> _handleDeepLink(Uri uri) async {
    try {
      debugPrint('Splash: 딥링크 처리 시작: $uri');

      // Supabase가 세션을 자동으로 처리하도록 기다림
      await Future.delayed(const Duration(milliseconds: 1000));

      // 세션 상태 재확인
      if (mounted) {
        final isLoggedIn = SupabaseService.instance.isLoggedIn;
        if (isLoggedIn) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint('Splash: 딥링크 처리 오류: $e');
    }
  }

  /// 다음 화면으로 이동
  /// 로그인 상태를 확인하고 적절한 화면으로 라우팅합니다.
  Future<void> _navigateToNextScreen() async {
    // 스플래시 화면 표시 시간 (2-3초)
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // 로그인 상태 확인
    final isLoggedIn = SupabaseService.instance.isLoggedIn;

    // 로그인 상태에 따라 화면 이동
    if (isLoggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 앱 로고
            const Text(
              'MuscleLog',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'AI 동작 기반 근육 분석 리포트',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 48),
            // 로딩 인디케이터
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
