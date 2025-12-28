import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../result/result_screen.dart';

/// 로딩 화면
/// AI 분석이 진행되는 동안 표시되는 화면입니다.
class LoadingScreen extends StatefulWidget {
  final String logId; // UUID String
  final String exerciseName;

  const LoadingScreen({
    super.key,
    required this.logId,
    required this.exerciseName,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _checkAnalysisStatus();
  }

  /// 분석 상태 확인 (폴링)
  void _checkAnalysisStatus() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;

      _fetchAnalysisStatus()
          .then((status) {
            if (status == 'COMPLETED') {
              // 분석 완료 - 결과 화면으로 이동
              if (mounted) {
                _navigateToResult();
              }
            } else if (status == 'FAILED') {
              // 분석 실패
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('분석에 실패했습니다.'),
                    backgroundColor: Colors.red,
                  ),
                );
                Navigator.of(context).pop();
              }
            } else {
              // 계속 대기
              _checkAnalysisStatus();
            }
          })
          .catchError((e) {
            debugPrint('상태 확인 오류: $e');
            _checkAnalysisStatus();
          });
    });
  }

  /// 분석 상태 조회
  Future<String> _fetchAnalysisStatus() async {
    try {
      final response = await SupabaseService.instance.client
          .from('workout_logs')
          .select('status')
          .eq('id', widget.logId)
          .single();

      final status = response['status']?.toString() ?? 'UNKNOWN';
      debugPrint('📊 분석 상태 조회: logId=${widget.logId}, status=$status');
      return status;
    } catch (e, stackTrace) {
      debugPrint('🔴 분석 상태 조회 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// 결과 화면으로 이동
  void _navigateToResult() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ResultScreen(logId: widget.logId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 중'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
              ),
              const SizedBox(height: 32),
              const Text(
                'AI 분석 진행 중...',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.exerciseName,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 32),
              const Text(
                '잠시만 기다려주세요.\n분석이 완료되면 자동으로 결과 화면으로 이동합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
