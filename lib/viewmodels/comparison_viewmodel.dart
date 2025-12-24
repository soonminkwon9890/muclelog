import 'package:flutter/foundation.dart';
import '../models/biomechanics_result.dart';
import '../services/supabase_service.dart';

/// 비교 분석 ViewModel
/// 2개의 분석 로그(과거 vs 현재)를 로드하고 비교합니다.
class ComparisonViewModel extends ChangeNotifier {
  BiomechanicsResult? _previousResult;
  BiomechanicsResult? _currentResult;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAnalyzing = false; // 분석 중 여부

  ComparisonViewModel();

  BiomechanicsResult? get previousResult => _previousResult;
  BiomechanicsResult? get currentResult => _currentResult;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get errorMessage => _errorMessage;
  bool get hasData => _previousResult != null && _currentResult != null;

  /// 비교 데이터 로드
  /// logIds는 정확히 2개여야 합니다 (첫 번째=과거, 두 번째=현재)
  /// 🔧 실제 DB 데이터를 가져와서 비교
  /// [logIds] workout_logs.id (UUID String) 리스트
  Future<void> loadComparisonData(List<String> logIds) async {
    if (logIds.length != 2) {
      _errorMessage = '비교하려면 정확히 2개의 기록이 필요합니다.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _isAnalyzing = false;
    notifyListeners();

    try {
      debugPrint('🟢 비교 데이터 로드 시작: 과거=${logIds[0]}, 현재=${logIds[1]}');

      // 🔧 workout_logs 테이블에서 직접 ai_analysis_result 조회
      final results = await Future.wait([
        _fetchAnalysisResultFromWorkoutLogs(logIds[0]),
        _fetchAnalysisResultFromWorkoutLogs(logIds[1]),
      ]);

      final previousData = results[0];
      final currentData = results[1];

      // 🔧 Null Check: 데이터가 없거나 비어있는지 확인
      if (previousData == null || currentData == null) {
        _isAnalyzing = false;
        _isLoading = false;

        if (previousData == null && currentData == null) {
          _errorMessage = '비교할 데이터가 충분하지 않습니다. 두 기록 모두 분석 결과가 없습니다.';
        } else if (previousData == null) {
          _errorMessage = '비교할 데이터가 충분하지 않습니다. 과거 기록의 분석 결과가 없습니다.';
        } else {
          _errorMessage = '비교할 데이터가 충분하지 않습니다. 현재 기록의 분석 결과가 없습니다.';
        }

        debugPrint('⚠️ [ComparisonViewModel] 분석 결과 부족: $_errorMessage');
        notifyListeners();
        return;
      } else {
        _isAnalyzing = false;

        // 🔧 ai_analysis_result JSON을 BiomechanicsResult로 변환
        _previousResult = BiomechanicsResult.fromAnalysisResult(previousData);
        _currentResult = BiomechanicsResult.fromAnalysisResult(currentData);

        debugPrint('✅ 비교 데이터 로드 완료');
        debugPrint(
          '   - 과거: 관절 ${_previousResult!.jointStats?.length ?? 0}개, 근육 ${_previousResult!.muscleScores?.length ?? 0}개',
        );
        debugPrint(
          '   - 현재: 관절 ${_currentResult!.jointStats?.length ?? 0}개, 근육 ${_currentResult!.muscleScores?.length ?? 0}개',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('🔴 비교 데이터 로드 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      _errorMessage = '데이터 로드 실패: $e';
      _isAnalyzing = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// workout_logs 테이블에서 ai_analysis_result 조회
  Future<Map<String, dynamic>?> _fetchAnalysisResultFromWorkoutLogs(
    String logId,
  ) async {
    try {
      final response = await SupabaseService.instance.client
          .from('workout_logs')
          .select('ai_analysis_result')
          .eq('id', logId)
          .maybeSingle();

      if (response == null) {
        debugPrint(
          '⚠️ [ComparisonViewModel] workout_logs에서 id=$logId를 찾을 수 없음',
        );
        return null;
      }

      final aiAnalysisResult = response['ai_analysis_result'];
      if (aiAnalysisResult == null) {
        debugPrint(
          '⚠️ [ComparisonViewModel] log_id=$logId의 ai_analysis_result가 null',
        );
        return null;
      }

      // JSONB 데이터를 Map으로 변환
      if (aiAnalysisResult is Map<String, dynamic>) {
        return aiAnalysisResult;
      } else {
        debugPrint(
          '⚠️ [ComparisonViewModel] ai_analysis_result가 Map이 아님: ${aiAnalysisResult.runtimeType}',
        );
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('🔴 [ComparisonViewModel] 데이터 조회 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      return null;
    }
  }

  /// 특정 근육의 Delta 계산
  double? getMuscleDelta(String muscleName) {
    if (!hasData) return null;

    final previousScore = _previousResult!.getMuscleScore(muscleName);
    final currentScore = _currentResult!.getMuscleScore(muscleName);

    if (previousScore == null || currentScore == null) return null;

    return currentScore - previousScore;
  }

  /// 특정 관절의 Delta 계산
  double? getJointContributionDelta(String jointName) {
    if (!hasData) return null;

    final previousStat = _previousResult!.getJointStat(jointName);
    final currentStat = _currentResult!.getJointStat(jointName);

    if (previousStat == null || currentStat == null) return null;

    return currentStat.contributionScore - previousStat.contributionScore;
  }

  /// 특정 관절의 ROM Delta 계산
  double? getRomDelta(String jointName) {
    if (!hasData) return null;

    final previousStat = _previousResult!.getJointStat(jointName);
    final currentStat = _currentResult!.getJointStat(jointName);

    if (previousStat == null || currentStat == null) return null;

    return currentStat.romDegrees - previousStat.romDegrees;
  }
}
