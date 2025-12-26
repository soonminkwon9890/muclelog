import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../widgets/muscle_heatmap_widget.dart';
import '../../widgets/skeleton_loader.dart';
import '../../viewmodels/comparison_viewmodel.dart';
import '../../models/biomechanics_result.dart';
import '../../utils/muscle_name_mapper.dart';

/// 비교 분석 화면
/// 2개의 분석 기록(과거 vs 현재)을 비교하여 변화량을 표시합니다.
class ComparisonScreen extends StatefulWidget {
  final List<Map<String, dynamic>> selectedLogs;

  const ComparisonScreen({super.key, required this.selectedLogs});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  late ComparisonViewModel _viewModel;

  // UI 상태
  int _currentMode = 0; // 0: 근육, 1: 관절
  String? _highlightedMuscle;
  String? _highlightedJoint;

  @override
  void initState() {
    super.initState();
    _viewModel = ComparisonViewModel();

    // selectedLogs에서 log_id 추출 (정확히 2개여야 함)
    if (widget.selectedLogs.length != 2) {
      // 경고 메시지 표시는 build에서 처리
      return;
    }

    final logIds = widget.selectedLogs
        .map((log) => (log['log_id'] ?? '').toString()) // UUID String
        .toList();

    _viewModel.loadComparisonData(logIds);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2개가 아니면 경고 표시
    if (widget.selectedLogs.length != 2) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('비교 분석'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  '비교하려면 정확히 2개의 기록이 필요합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  '현재 선택된 기록: ${widget.selectedLogs.length}개',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('돌아가기'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        final viewModel = _viewModel;

        if (viewModel.isLoading) {
    return Scaffold(
      appBar: AppBar(
              title: const Text('비교 분석'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (viewModel.errorMessage != null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('비교 분석'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
            body: Center(
        child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      viewModel.errorMessage!,
            textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('돌아가기'),
                    ),
                  ],
                ),
          ),
        ),
      );
    }

        // 분석 중인 경우 스켈레톤 로더 표시
        if (viewModel.isAnalyzing) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('비교 분석'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
            body: Column(
              children: [
                // 히트맵 스켈레톤
                SizedBox(
                  height: 250,
                  child: Container(
                    margin: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
                // 모드 선택 탭
                _buildModeSelector(),
                // 리스트 스켈레톤
                Expanded(
                  child: SkeletonLoader(isMuscleMode: _currentMode == 0),
                ),
              ],
            ),
          );
        }

        if (!viewModel.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('비교 분석'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '비교할 데이터가 없습니다.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '분석이 완료된 기록만 비교할 수 있습니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('비교 분석 (과거 vs 현재)'),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
          ),
          body: Column(
            children: [
              // Section A: 듀얼 바디 히트맵 (고정 높이)
              SizedBox(height: 250, child: _buildDualHeatmapSection(viewModel)),
              // Section B: 모드 선택 탭
              _buildModeSelector(),
              // Section C: 정밀 수치 아코디언 리스트 (Expanded로 남은 공간 차지)
              Expanded(
                child: _currentMode == 0
                    ? _buildMuscleAccordionList(viewModel)
                    : _buildJointAccordionList(viewModel),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 듀얼 바디 히트맵 섹션
  Widget _buildDualHeatmapSection(ComparisonViewModel viewModel) {
    if (!viewModel.hasData) {
      return const Center(
        child: Text('데이터가 없습니다.', style: TextStyle(color: Colors.grey)),
      );
    }

    // 현재 데이터로 히트맵 표시
    final currentResult = viewModel.currentResult!;
    final muscleData = <String, double>{};
    if (currentResult.muscleScores != null) {
      for (final entry in currentResult.muscleScores!.entries) {
        if (entry.value.score > 0) {
          muscleData[entry.key] = entry.value.score;
        }
      }
    }

    if (muscleData.isEmpty) {
      return const Center(
        child: Text('근육 데이터가 없습니다.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // 전면 히트맵
          Expanded(
            child: MuscleHeatmapWidget(
              isFront: true,
              muscleData: muscleData,
              mode: _currentMode == 0 ? 'MUSCLE' : 'JOINT',
              biomechPattern: currentResult.biomechPattern,
              highlightedMuscle: _highlightedMuscle,
            ),
          ),
          const SizedBox(width: 8),
          // 후면 히트맵
          Expanded(
            child: MuscleHeatmapWidget(
              isFront: false,
              muscleData: muscleData,
              mode: _currentMode == 0 ? 'MUSCLE' : 'JOINT',
              biomechPattern: currentResult.biomechPattern,
              highlightedMuscle: _highlightedMuscle,
            ),
          ),
        ],
      ),
    );
  }

  /// 모드 선택 탭
  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _currentMode,
        onValueChanged: (value) {
          if (value != null) {
            setState(() {
              _currentMode = value;
            });
          }
        },
        children: const {
          0: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('근육 (Muscle)'),
          ),
          1: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('관절 (Joint)'),
          ),
        },
      ),
    );
  }

  /// 근육 모드 아코디언 리스트 (비교 모드)
  Widget _buildMuscleAccordionList(ComparisonViewModel viewModel) {
    if (!viewModel.hasData) {
      return const Center(
        child: Text('근육 데이터가 없습니다.', style: TextStyle(color: Colors.grey)),
      );
    }

    final currentResult = viewModel.currentResult!;
    final previousResult = viewModel.previousResult!;

    // 백엔드 데이터만 사용
    final muscleData = <String, double>{};
    if (currentResult.muscleScores != null) {
      for (final entry in currentResult.muscleScores!.entries) {
        if (entry.value.score > 0) {
          muscleData[entry.key] = entry.value.score;
        }
      }
    }

    if (muscleData.isEmpty) {
      return const Center(
        child: Text('N/A', style: TextStyle(color: Colors.grey)),
      );
    }

    // 점수 기준으로 정렬
    final sorted = muscleData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final entry = sorted[index];
        final muscleName = entry.key;
        final currentScore = entry.value;
        final previousScore = previousResult.getMuscleScore(muscleName);
        final isHighlighted = _highlightedMuscle == muscleName;

        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          color: isHighlighted ? Colors.blue.shade50 : Colors.white,
          child: ListTile(
            title: Text(MuscleNameMapper.localize(muscleName)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
        children: [
                Text(
                  '${currentScore.toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (previousScore != null)
                  Text(
                    '${(currentScore - previousScore).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: (currentScore - previousScore) >= 0
                          ? Colors.green
                          : Colors.red,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            onTap: () {
              setState(() {
                _highlightedMuscle = muscleName;
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _highlightedMuscle = null;
                  });
                }
              });
            },
          ),
        );
      },
    );
  }

  /// 관절 모드 아코디언 리스트 (비교 모드)
  Widget _buildJointAccordionList(ComparisonViewModel viewModel) {
    if (!viewModel.hasData) {
      return const Center(
        child: Text('관절 데이터가 없습니다.', style: TextStyle(color: Colors.grey)),
      );
    }

    final currentResult = viewModel.currentResult!;
    final previousResult = viewModel.previousResult!;

    // 백엔드 데이터만 사용
    final jointData = <String, JointStat>{};
    if (currentResult.jointStats != null) {
      for (final entry in currentResult.jointStats!.entries) {
        if (entry.value.contributionScore > 0) {
          jointData[entry.key] = entry.value;
        }
      }
    }

    if (jointData.isEmpty) {
      return const Center(
        child: Text('N/A', style: TextStyle(color: Colors.grey)),
      );
    }

    // Contribution 기준으로 정렬
    final sorted = jointData.entries.toList()
      ..sort(
        (a, b) =>
            b.value.contributionScore.compareTo(a.value.contributionScore),
      );

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final entry = sorted[index];
        final jointName = entry.key;
        final currentStat = entry.value;
        final previousStat = previousResult.getJointStat(jointName);
        final isExpanded = index == 0; // 첫 번째 항목만 확장
        final isHighlighted = _highlightedJoint == jointName;

    return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          color: isHighlighted ? Colors.blue.shade50 : Colors.white,
      child: ExpansionTile(
            initiallyExpanded: isExpanded,
            title: Text(MuscleNameMapper.localize(jointName)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
          children: [
                Text(
                  '${currentStat.contributionScore.toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (previousStat != null)
                    Text(
                    '${(currentStat.contributionScore - previousStat.contributionScore).toStringAsFixed(1)}%',
                      style: TextStyle(
                      color:
                          (currentStat.contributionScore -
                                  previousStat.contributionScore) >=
                              0
                          ? Colors.green
                          : Colors.red,
                      fontSize: 12,
                      ),
                    ),
                  ],
            ),
            onExpansionChanged: (expanded) {
              if (expanded) {
                setState(() {
                  _highlightedJoint = jointName;
                });
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      _highlightedJoint = null;
                    });
                  }
                });
              }
            },
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ROM: ${currentStat.romDegrees.toStringAsFixed(1)}°'),
                    Text(
                      '안정성: ${currentStat.stabilityScore.toStringAsFixed(1)}점',
                    ),
            Text(
                      '기여도: ${currentStat.contributionScore.toStringAsFixed(1)}%',
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
      },
    );
  }
}
