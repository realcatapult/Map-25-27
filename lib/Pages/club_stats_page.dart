import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/check_in_service.dart';
import '../theme/app_theme.dart';

/// Club statistics: every club day, and the attendance sheet for each.
///
/// Open to club admins for their own club, and to school admins for any club.
class ClubStatsPage extends StatefulWidget {
  const ClubStatsPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<ClubStatsPage> createState() => _ClubStatsPageState();
}

class _ClubStatsPageState extends State<ClubStatsPage> {
  final CheckInService _service = CheckInService();

  /// One report per club day, kept for the life of the screen. Without this
  /// the list re-queried Firestore on every scroll.
  final Map<String, Future<ClubDayReport>> _reports = {};

  Future<ClubDayReport> _reportFor(String dateKey) => _reports.putIfAbsent(
    dateKey,
    () => _service.buildReport(widget.groupId, dateKey),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: const Text('Club Statistics'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.groupName,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.watchClubDays(widget.groupId),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not load club days.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final days = snap.data!.docs;
          if (days.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No club days yet.\nStart one from Club Day to begin tracking attendance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.4, color: cs.onSurfaceVariant),
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: days.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = days[i].data();
              final key = (d['dateKey'] as String?) ?? days[i].id;
              final isOpen = d['isOpen'] == true;
              return _DayTile(
                dateKey: key,
                isOpen: isOpen,
                report: _reportFor(key),
                groupId: widget.groupId,
                groupName: widget.groupName,
              );
            },
          );
        },
      ),
    );
  }
}

/// One club day in the list. The report is supplied already-memoised by
/// the parent, so recycling this row costs nothing.
class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.dateKey,
    required this.isOpen,
    required this.report,
    required this.groupId,
    required this.groupName,
  });

  final String dateKey;
  final bool isOpen;
  final Future<ClubDayReport> report;
  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<ClubDayReport>(
      future: report,
      builder: (context, snap) {
        final r = snap.data;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: cs.primary.withValues(alpha: 0.15),
            child: Icon(Icons.event_available, color: cs.primary, size: 20),
          ),
          title: Row(
            children: [
              Text(
                _pretty(dateKey),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (isOpen) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'OPEN',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: r == null
              ? const Text('Loading…')
              : Text(
                  '${r.presentCount} of ${r.totalMembers} present'
                  '  •  ${(r.attendanceRate * 100).round()}%',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ClubDaySheetPage(
                groupId: groupId,
                groupName: groupName,
                dateKey: dateKey,
              ),
            ),
          ),
        );
      },
    );
  }

  static String _pretty(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// The attendance spreadsheet for one club day: one row per club member,
/// present or absent, with the time they signed in.
class ClubDaySheetPage extends StatefulWidget {
  const ClubDaySheetPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.dateKey,
  });

  final String groupId;
  final String groupName;
  final String dateKey;

  @override
  State<ClubDaySheetPage> createState() => _ClubDaySheetPageState();
}

class _ClubDaySheetPageState extends State<ClubDaySheetPage> {
  final CheckInService _service = CheckInService();
  late Future<ClubDayReport> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.buildReport(widget.groupId, widget.dateKey);
  }

  void _reload() {
    setState(() {
      _future = _service.buildReport(widget.groupId, widget.dateKey);
    });
  }

  Future<void> _copyCsv(ClubDayReport report) async {
    final csv = _service.reportToCsv(report, clubName: widget.groupName);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied as CSV — paste into Sheets or Excel'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GradientAppBarBackground(),
        title: Text(widget.dateKey),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<ClubDayReport>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Could not build the sheet.'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;

          return Column(
            children: [
              _summary(r),
              const Divider(height: 1),
              Expanded(child: _table(r)),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<ClubDayReport>(
        future: _future,
        builder: (context, snap) => snap.hasData
            ? FloatingActionButton.extended(
                onPressed: () => _copyCsv(snap.data!),
                icon: const Icon(Icons.copy_all),
                label: const Text('Copy CSV'),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _summary(ClubDayReport r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          _stat('PRESENT', '${r.presentCount}', Colors.green),
          _stat('ABSENT', '${r.absentCount}', Colors.orange),
          _stat('MEMBERS', '${r.totalMembers}', null),
          _stat('RATE', '${(r.attendanceRate * 100).round()}%', null),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color? color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color ?? cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontally scrollable so the columns keep real widths on a phone
  /// rather than being squeezed into something unreadable.
  Widget _table(ClubDayReport r) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 54,
          headingTextStyle: TextStyle(
            fontSize: 11.5,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
          columns: const [
            DataColumn(label: Text('NAME')),
            DataColumn(label: Text('EMAIL')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('SIGNED IN')),
          ],
          rows: [
            for (final row in r.rows)
              DataRow(
                // A faint wash behind absent rows, so the block of people who
                // came is visible before reading a single name.
                color: row.present
                    ? null
                    : WidgetStatePropertyAll(
                        cs.onSurface.withValues(alpha: 0.035),
                      ),
                cells: [
                  DataCell(
                    Text(
                      row.displayName,
                      style: TextStyle(
                        fontWeight: row.present
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: row.present
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      row.email,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant.withValues(
                          alpha: row.present ? 1 : 0.6,
                        ),
                      ),
                    ),
                  ),
                  DataCell(_statusPill(row.present, row.method)),
                  DataCell(
                    Text(
                      row.checkedInAt == null ? '—' : _clock(row.checkedInAt!),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: row.present
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: row.present
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(bool present, String? method) {
    final cs = Theme.of(context).colorScheme;
    final color = present ? Colors.green : cs.onSurfaceVariant;
    final label = present
        ? (method == 'manual' ? 'Present (hand)' : 'Present')
        : 'Absent';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}
