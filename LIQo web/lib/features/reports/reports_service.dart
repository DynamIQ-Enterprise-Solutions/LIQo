import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../shared/models/paged.dart';

// Problem reports (Round 19, owner decisions 2026-10-23): mall owners, mall
// admins and store owners report a problem from the top bar; the superadmin
// and the reporter talk in a thread until it is resolved or closed.

Map<String, dynamic> _m(Object? v) => v as Map<String, dynamic>;
DateTime _t(Object? v) => DateTime.tryParse('$v') ?? DateTime.now();

/// The kinds of report, in plain words.
const reportTypeLabels = {
  'broken': 'Something broke',
  'wrong_data': 'Wrong data',
  'question': 'Question',
  'idea': 'Idea',
};

const reportStatusLabels = {
  'new': 'New',
  'in_progress': 'In progress',
  'resolved': 'Resolved',
  'closed': 'Closed',
};

class ProblemReport {
  const ProblemReport({
    required this.id,
    required this.reporterId,
    required this.reporter,
    this.reporterEmail,
    this.reporterRole,
    required this.type,
    required this.subject,
    required this.body,
    this.pagePath,
    required this.status,
    required this.open,
    required this.waiting,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
    this.closedBy,
  });

  final int id;
  final int reporterId;
  final String reporter;
  final String? reporterEmail;
  final String? reporterRole;
  final String type;
  final String subject;
  final String body;
  final String? pagePath;
  final String status;
  final bool open;

  /// The superadmin still owes an answer.
  final bool waiting;
  final int messageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? closedBy;

  factory ProblemReport.fromJson(Map<String, dynamic> j) => ProblemReport(
        id: j['id'] as int,
        reporterId: j['reporterId'] as int,
        reporter: j['reporter'] as String? ?? '',
        reporterEmail: j['reporterEmail'] as String?,
        reporterRole: j['reporterRole'] as String?,
        type: j['type'] as String,
        subject: j['subject'] as String,
        body: j['body'] as String? ?? '',
        pagePath: j['pagePath'] as String?,
        status: j['status'] as String,
        open: j['open'] == true,
        waiting: j['waiting'] == true,
        messageCount: (j['messageCount'] as num?)?.toInt() ?? 0,
        createdAt: _t(j['createdAt']),
        updatedAt: _t(j['updatedAt']),
        closedBy: j['closedBy'] as String?,
      );
}

class ReportMessage {
  const ReportMessage({required this.id, required this.authorId, required this.author, this.authorRole, required this.body, required this.createdAt});

  final int id;
  final int authorId;
  final String author;
  final String? authorRole;
  final String body;
  final DateTime createdAt;

  factory ReportMessage.fromJson(Map<String, dynamic> j) => ReportMessage(
        id: j['id'] as int,
        authorId: j['authorId'] as int,
        author: j['author'] as String? ?? '',
        authorRole: j['authorRole'] as String?,
        body: j['body'] as String,
        createdAt: _t(j['createdAt']),
      );
}

/// A report with its thread.
class ReportThread {
  const ReportThread(this.report, this.messages);

  final ProblemReport report;
  final List<ReportMessage> messages;

  factory ReportThread.fromJson(Map<String, dynamic> j) =>
      ReportThread(ProblemReport.fromJson(_m(j['report'])), [for (final m in j['messages'] as List<dynamic>? ?? const []) ReportMessage.fromJson(_m(m))]);
}

class ReportsService {
  ReportsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<ProblemReport> create({required String type, required String subject, required String body, String? pagePath}) async => ProblemReport.fromJson(
        _m(_m((await _client.dio.post('/reports', data: {'type': type, 'subject': subject, 'body': body, if (pagePath != null) 'pagePath': pagePath})).data)['report']),
      );

  Future<PagedResult<ProblemReport>> mine(ListQuery q) async => PagedResult.fromJson(_m((await _client.dio.get('/reports/mine', queryParameters: q.toParams())).data), ProblemReport.fromJson);

  Future<PagedResult<ProblemReport>> list(ListQuery q) async => PagedResult.fromJson(_m((await _client.dio.get('/reports', queryParameters: q.toParams())).data), ProblemReport.fromJson);

  Future<ReportThread> get(int id) async => ReportThread.fromJson(_m((await _client.dio.get('/reports/$id')).data));

  Future<ReportThread> reply(int id, String body) async => ReportThread.fromJson(_m((await _client.dio.post('/reports/$id/messages', data: {'body': body})).data));

  Future<ReportThread> setStatus(int id, String status) async => ReportThread.fromJson(_m((await _client.dio.put('/reports/$id/status', data: {'status': status})).data));
}

/// The signed-in person's latest reports (My account).
final myReportsProvider = FutureProvider.autoDispose<PagedResult<ProblemReport>>((ref) => ReportsService().mine(const ListQuery(pageSize: 5)));
