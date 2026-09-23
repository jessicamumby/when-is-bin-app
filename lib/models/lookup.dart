import 'address_lookup.dart';
import 'schedule.dart';

/// Progress detail for a running lookup.
class LookupProgress {
  const LookupProgress({this.stage, this.message});

  final String? stage;
  final String? message;

  factory LookupProgress.fromJson(Map<String, dynamic> json) {
    return LookupProgress(
      stage: json['stage'] as String?,
      message: json['message'] as String?,
    );
  }
}

/// A lookup job. `done` and `failed` are terminal; the rest need polling.
class Lookup {
  const Lookup({
    required this.id,
    required this.status,
    this.createdAt,
    this.completedAt,
    this.council,
    this.expectedWaitSeconds,
    this.successRate,
    this.result,
    this.progress,
    this.detail,
  });

  final String id;
  final String status;
  final String? createdAt;
  final String? completedAt;
  final Council? council;
  final int? expectedWaitSeconds;
  final double? successRate;
  final Schedule? result;
  final LookupProgress? progress;
  final String? detail;

  static const _pendingStatuses = {'queued', 'running', 'partial'};

  bool get isPending => _pendingStatuses.contains(status);
  bool get isTerminal => status == 'done' || status == 'failed';

  factory Lookup.fromJson(Map<String, dynamic> json) {
    return Lookup(
      id: json['id'] as String,
      status: json['status'] as String,
      createdAt: json['created_at'] as String?,
      completedAt: json['completed_at'] as String?,
      council: json['council'] == null
          ? null
          : Council.fromJson(json['council'] as Map<String, dynamic>),
      expectedWaitSeconds: json['expected_wait_seconds'] as int?,
      successRate: (json['success_rate'] as num?)?.toDouble(),
      result: json['result'] == null
          ? null
          : Schedule.fromJson(json['result'] as Map<String, dynamic>),
      progress: json['progress'] == null
          ? null
          : LookupProgress.fromJson(json['progress'] as Map<String, dynamic>),
      detail: json['detail'] as String?,
    );
  }
}
