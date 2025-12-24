import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'services/supabase_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 변수 로드
  try {
    await Env.load();
  } catch (e) {
    debugPrint('환경 변수 로드 실패: $e');
  }

  // Supabase 초기화
  try {
    debugPrint('🔵 Supabase 초기화 시작...');
    debugPrint('🔵 Supabase URL: ${Env.supabaseUrl}');
    debugPrint('🔵 Deep Link URL: ${Env.deepLinkRedirectUrl}');
    await SupabaseService.initialize();
    debugPrint('🟢 Supabase 초기화 완료');
  } catch (e, stackTrace) {
    debugPrint('🔴 Supabase 초기화 실패: $e');
    debugPrint('🔴 스택 트레이스: $stackTrace');
  }

  // 세로 방향 고정
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MuscleLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// 인증 상태에 따라 화면을 분기하는 위젯
/// Supabase의 인증 상태 변경을 실시간으로 감지하여 화면을 전환합니다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // 로딩 중일 때
        if (snapshot.connectionState == ConnectionState.waiting) {
      return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
      );
    }

        // 세션이 있으면 -> 대시보드로
        final session = snapshot.data?.session;
        if (session != null) {
          return const DashboardScreen();
        }

        // 세션이 없으면 -> 로그인 화면으로
      return const LoginScreen();
      },
    );
  }
}
