import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:login_ui/Pages/chat_list_page.dart';
import 'package:login_ui/Pages/chat_room_page.dart';
import 'package:login_ui/Pages/direct_message_page.dart';
import 'package:login_ui/Pages/settings_page.dart';
import 'package:login_ui/Pages/search_page.dart';
import 'package:login_ui/Pages/discover_page.dart';
import 'package:login_ui/Pages/my_check_in_code_page.dart';
import 'package:login_ui/components/interests_picker_dialog.dart';
import 'package:login_ui/components/unity_logo.dart';
import 'package:login_ui/services/chat_service.dart';
import 'package:login_ui/theme/app_theme.dart';
import 'club_day_page.dart';

class _CalendarEvent {
  final String id;
  final String title;
  final String description;
  final String groupId;
  final String groupName;
  final DateTime date;

  const _CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.groupId,
    required this.groupName,
    required this.date,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ChatService _chatService = ChatService();
  // Cache the stream ONCE. Calling getUserGroups() inside build() created a new
  // stream every rebuild → StreamBuilder re-subscribed → content blanked to
  // 'waiting' → flicker. Created once here, it stays subscribed.
  late final Stream<QuerySnapshot> _groupsStream = _chatService.getUserGroups();
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _selectedIndex = 0;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoadingNotifications = false;

  Map<DateTime, List<_CalendarEvent>> _eventsByDay = {};
  bool _isLoadingEvents = false;
  final Map<String, String> _groupNamesById = {};
  final Set<String> _enabledGroupIds = {};
  Set<String> _lastGroupIds = {};

  /// Static so it survives a second HomePage State being created in the
  /// same session, which an instance field would not.
  static bool _handledInterestsOnboarding = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowInterestsOnboarding();
    });
  }

  Future<void> _maybeShowInterestsOnboarding() async {
    if (_handledInterestsOnboarding || !mounted) return;

    _handledInterestsOnboarding = true;

    final shouldShow = await _chatService.shouldShowInterestsOnboarding();
    if (!mounted || !shouldShow) return;

    final existingInterests = await _chatService.getCurrentUserInterests();
    if (!mounted) return;

    final selected = await showInterestsPickerDialog(
      context,
      initialSelection: existingInterests,
      isOnboarding: true,
    );

    // Marked straight away, whatever they chose. Asking once is the promise
    // of onboarding; dismissing is an answer, not a postponement.
    await _chatService.markInterestsOnboardingSeen();

    if (selected == null || selected.isEmpty) return;

    await _chatService.updateCurrentUserInterests(selected);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Preferences saved. Your recommendations are personalized.',
        ),
      ),
    );
  }

  DateTime _normalizeDay(DateTime day) {
    return DateTime.utc(day.year, day.month, day.day);
  }

  /// Open the club's Club Day session for the tapped event's club. Admin
  /// status comes from the group's admins list, so only officers get the
  /// scanner and the open/close controls. Firestore rules re-check it on
  /// every write.
  Future<void> _openAttendance(_CalendarEvent event) async {
    if (event.groupId.isEmpty) return;

    final email = FirebaseAuth.instance.currentUser?.email;
    bool isAdmin = false;
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(event.groupId)
          .get();
      final data = groupDoc.data();
      isAdmin =
          email != null &&
          data != null &&
          _chatService.hasGroupPermission(data, email, 'manage_check_ins');
    } catch (_) {
      // Fall through as a non-admin: the roster is still worth showing.
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClubDayPage(
          groupId: event.groupId,
          groupName: event.groupName,
          isAdmin: isAdmin,
        ),
      ),
    );
  }

  List<_CalendarEvent> _getEventsForDay(DateTime day) {
    final normalizedDay = _normalizeDay(day);
    return _eventsByDay[normalizedDay] ?? [];
  }

  void _syncGroups(List<QueryDocumentSnapshot> groupDocs) {
    final groupIds = groupDocs.map((doc) => doc.id).toSet();
    if (setEquals(groupIds, _lastGroupIds)) {
      return;
    }

    _groupNamesById.clear();
    for (final doc in groupDocs) {
      final data = doc.data() as Map<String, dynamic>;
      _groupNamesById[doc.id] = data['name'] ?? 'Group';
    }

    if (_enabledGroupIds.isEmpty) {
      _enabledGroupIds.addAll(groupIds);
    } else {
      _enabledGroupIds.removeWhere((id) => !groupIds.contains(id));
      for (final id in groupIds) {
        _enabledGroupIds.add(id);
      }
    }

    _lastGroupIds = groupIds;
    _loadEventsForGroups(_enabledGroupIds.toList());
    _loadNotifications(groupDocs);
  }

  Future<void> _loadNotifications(List<QueryDocumentSnapshot> groupDocs) async {
    if (_isLoadingNotifications) return;
    setState(() {
      _isLoadingNotifications = true;
    });

    final groups = groupDocs.map<Map<String, String>>((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {'id': doc.id, 'name': (data['name'] ?? 'Group').toString()};
    }).toList();

    final items = await _chatService.getRecentNotifications(groups);

    if (!mounted) return;
    setState(() {
      _notifications = items;
      _isLoadingNotifications = false;
    });
  }

  String _formatNotificationSubtitle(Map<String, dynamic> item) {
    if ((item['type'] as String?) == 'eventReminder') {
      final ts = item['date'] as Timestamp?;
      if (ts == null) return '';
      final date = ts.toDate();
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour < 12 ? 'AM' : 'PM';
      return '${date.month}/${date.day} at $hour:$minute $period';
    }
    final sender = (item['senderEmail'] as String?) ?? '';
    if (sender.isEmpty) return '';
    final name = sender.split('@').first;
    return 'From $name';
  }

  String _formatNotificationTitle(Map<String, dynamic> item) {
    final type = item['type'] as String?;
    if (type == 'eventReminder') {
      return '${item['groupName'] ?? 'Group'} reminder';
    }
    if (type == 'dm') {
      return item['otherEmail'] as String? ?? 'Direct message';
    }
    return item['groupName'] as String? ?? 'Group';
  }

  String _formatNotificationBody(Map<String, dynamic> item) {
    if ((item['type'] as String?) == 'eventReminder') {
      final title = (item['title'] as String?) ?? 'Upcoming event';
      final description = (item['description'] as String?) ?? '';
      return description.isEmpty ? title : '$title • $description';
    }
    final text = (item['text'] as String?) ?? '';
    final imageUrl = item['imageUrl'] as String?;
    if (text.isNotEmpty) return text;
    if (imageUrl != null) return 'Sent an image';
    return 'New message';
  }

  void _openNotification(Map<String, dynamic> item) {
    final type = item['type'] as String?;
    if (type == 'eventReminder') {
      final groupId = item['groupId'] as String?;
      final groupName = item['groupName'] as String?;
      if (groupId == null || groupName == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChatRoomPage(groupId: groupId, groupName: groupName),
        ),
      );
      return;
    }
    if (type == 'dm') {
      final threadId = item['threadId'] as String?;
      final otherEmail = item['otherEmail'] as String?;
      if (threadId == null || otherEmail == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              DirectMessagePage(threadId: threadId, otherEmail: otherEmail),
        ),
      );
      return;
    }

    final groupId = item['groupId'] as String?;
    final groupName = item['groupName'] as String?;
    if (groupId == null || groupId.isEmpty || groupName == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChatRoomPage(groupId: groupId, groupName: groupName),
      ),
    );
  }

  void _openClubChat(_CalendarEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatRoomPage(groupId: event.groupId, groupName: event.groupName),
      ),
    );
  }

  List<_CalendarEvent> _upcomingEvents() {
    final today = _normalizeDay(DateTime.now());
    return _eventsByDay.values
        .expand((events) => events)
        .where((event) => !_normalizeDay(event.date).isBefore(today))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _loadEventsForGroups(List<String> groupIds) async {
    if (_isLoadingEvents) return;
    setState(() {
      _isLoadingEvents = true;
    });

    final Map<DateTime, List<_CalendarEvent>> nextEvents = {};
    for (final groupId in groupIds) {
      final groupName = _groupNamesById[groupId] ?? 'Group';
      final events = await _chatService.getGroupEvents(groupId);

      for (final event in events) {
        final title = event['title'] as String? ?? 'Event';
        final description = event['description'] as String? ?? '';
        final dateValue = event['date'];
        DateTime date;
        if (dateValue is Timestamp) {
          date = dateValue.toDate();
        } else if (dateValue is DateTime) {
          date = dateValue;
        } else {
          continue;
        }

        final normalized = _normalizeDay(date);
        nextEvents.putIfAbsent(normalized, () => []);
        nextEvents[normalized]!.add(
          _CalendarEvent(
            id: event['id'] as String? ?? '',
            title: title,
            description: description,
            groupId: groupId,
            groupName: groupName,
            date: date,
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _eventsByDay = nextEvents;
      _isLoadingEvents = false;
    });
  }

  void _showCalendarFilterDialog(List<QueryDocumentSnapshot> groupDocs) {
    if (groupDocs.isEmpty) return;

    final groupNames = {
      for (final doc in groupDocs)
        doc.id: (doc.data() as Map<String, dynamic>)['name'] ?? 'Group',
    };

    final selected = <String>{..._enabledGroupIds};
    if (selected.isEmpty) {
      selected.addAll(groupNames.keys);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Calendar Filters'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: groupNames.entries.map((entry) {
                final isSelected = selected.contains(entry.key);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: isSelected,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selected.add(entry.key);
                      } else {
                        selected.remove(entry.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  selected
                    ..clear()
                    ..addAll(groupNames.keys);
                });
              },
              child: const Text('Select All'),
            ),
            TextButton(
              onPressed: () {
                setDialogState(() {
                  selected.clear();
                });
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _enabledGroupIds
                    ..clear()
                    ..addAll(selected);
                });
                _loadEventsForGroups(_enabledGroupIds.toList());
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy),
              child: const Text('Apply', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  final List<Map<String, String>> _announcements = [
    {
      'title': 'Club Elections Tomorrow',
      'time': '2 hours ago',
      'from': 'President',
    },
    {'title': 'Fundraising Event', 'time': '5 hours ago', 'from': 'Secretary'},
    {'title': 'Meeting Friday', 'time': '1 day ago', 'from': 'President'},
  ];

  void _onItemTapped(int index) {
    // Every tab is a child of this screen's IndexedStack now, so switching
    // is a state change rather than a route push. Pushing Chat, Search and
    // Settings as routes is what used to hide the bottom bar.
    setState(() {
      _selectedIndex = index;
    });
  }

  // Spacing scale. One gutter and one section gap keep the vertical rhythm
  // even; the previous layout mixed 0/8/16 margins per card and read as drift.
  static const double _gutter = 16;
  static const double _sectionGap = 14;

  /// Section shell. Every band on this page is the same surface with the same
  /// padding and radius, so the eye tracks content rather than containers.
  Widget _section({
    required String title,
    required Widget child,
    Widget? action,
    bool loading = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (action != null) action,
            ],
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _emptyNote(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildHomeBody({
    required List<QueryDocumentSnapshot> groupDocs,
    required bool isInitialLoading,
    required bool showNotifications,
  }) {
    final cs = Theme.of(context).colorScheme;

    // One page, one scroll. The old layout split the viewport into fixed
    // 2:4:3 flex panels, so each band became a cramped window that clipped its
    // own content - the calendar alone needs more height than its share
    // allowed. Sections now take their natural height and the page scrolls.
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _refreshHome(groupDocs),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                _gutter,
                _gutter,
                _gutter,
                // Clear the bottom nav and the gesture inset so the last card
                // never sits under them.
                _gutter + MediaQuery.of(context).padding.bottom + 8,
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (showNotifications) ...[
                  _studentWelcome(),
                  const SizedBox(height: _sectionGap),
                  _upcomingEventsSection(),
                  const SizedBox(height: _sectionGap),
                ],
                if (showNotifications) ...[
                  _section(
                    title: 'NOTIFICATIONS',
                    loading: _isLoadingNotifications,
                    child: _notificationsList(),
                  ),
                  const SizedBox(height: _sectionGap),
                ],
                _section(
                  title: 'CALENDAR',
                  loading: _isLoadingEvents,
                  action: IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    tooltip: 'Calendar settings',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: cs.onSurfaceVariant,
                    onPressed: groupDocs.isEmpty
                        ? null
                        : () => _showCalendarFilterDialog(groupDocs),
                  ),
                  child: _calendarBlock(),
                ),
                const SizedBox(height: _sectionGap),
                _section(title: 'ANNOUNCEMENTS', child: _announcementsList()),
              ],
            ),
          ),
          if (isInitialLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _studentWelcome() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.cyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Make this week yours.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Find an activity you enjoy, meet people with similar interests, '
            'or see what your clubs are doing next.',
            style: TextStyle(color: Colors.white, height: 1.4),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiscoverPage()),
            ),
            icon: const Icon(Icons.explore_outlined),
            label: const Text('Explore clubs'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingEventsSection() {
    final events = _upcomingEvents().take(3).toList();
    return _section(
      title: 'COMING UP',
      child: events.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _emptyNote(
                  'No upcoming club events yet. Explore clubs to find a new '
                  'activity or group to connect with.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DiscoverPage()),
                    ),
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Find something to try'),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                for (var i = 0; i < events.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                  _upcomingEventRow(events[i]),
                ],
              ],
            ),
    );
  }

  Widget _upcomingEventRow(_CalendarEvent event) {
    final cs = Theme.of(context).colorScheme;
    final dateLabel =
        '${event.date.month}/${event.date.day} · '
        '${event.date.hour % 12 == 0 ? 12 : event.date.hour % 12}:'
        '${event.date.minute.toString().padLeft(2, '0')} '
        '${event.date.hour < 12 ? 'AM' : 'PM'}';

    return InkWell(
      onTap: () => _openClubChat(event),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.event_outlined, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$dateLabel · ${event.groupName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshHome(List<QueryDocumentSnapshot> groupDocs) async {
    // Both loaders guard on their own in-flight flags, so clear them first;
    // a pull that silently did nothing is worse than a slow one.
    _isLoadingNotifications = false;
    _isLoadingEvents = false;
    await _loadNotifications(groupDocs);
    final ids = _groupNamesById.keys.toList();
    if (ids.isNotEmpty) {
      _isLoadingEvents = false;
      await _loadEventsForGroups(ids);
    }
  }

  Widget _notificationsList() {
    if (_notifications.isEmpty) {
      return _emptyNote('Nothing new right now.');
    }

    final cs = Theme.of(context).colorScheme;
    // Capped rather than scrolled. A nested scroller inside a page scroller is
    // the thing that felt cut off; a cap keeps the band predictable.
    const maxShown = 4;
    final shown = _notifications.take(maxShown).toList();
    final hidden = _notifications.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          _notificationRow(shown[i]),
        ],
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '$hidden more',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _notificationRow(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = _formatNotificationSubtitle(item);

    return InkWell(
      onTap: () => _openNotification(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatNotificationTitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatNotificationBody(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarBlock() {
    final cs = Theme.of(context).colorScheme;
    final events = _selectedDay == null
        ? const <_CalendarEvent>[]
        : _getEventsForDay(_selectedDay!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _getEventsForDay,
          // Horizontal only: the calendar's vertical drag used to fight the
          // page scroll, which is most of why scrolling felt unpredictable.
          availableGestures: AvailableGestures.horizontalSwipe,
          rowHeight: 44,
          daysOfWeekHeight: 22,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarStyle: CalendarStyle(
            cellMargin: const EdgeInsets.all(5),
            outsideDaysVisible: false,
            selectedDecoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(
              color: cs.onPrimary,
              fontWeight: FontWeight.w700,
            ),
            todayDecoration: BoxDecoration(
              color: cs.secondary.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
            markerDecoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            markerSize: 4,
            markersMaxCount: 3,
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            headerPadding: const EdgeInsets.only(bottom: 6),
            leftChevronPadding: EdgeInsets.zero,
            rightChevronPadding: EdgeInsets.zero,
            titleTextStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _selectedDay != null
              ? 'Events for ${_selectedDay!.month}/${_selectedDay!.day}/${_selectedDay!.year}'
              : 'No date selected',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        const SizedBox(height: 2),
        if (events.isEmpty)
          _emptyNote('No events scheduled.')
        else
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
            _eventRow(events[i]),
          ],
      ],
    );
  }

  Widget _eventRow(_CalendarEvent event) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openAttendance(event),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A dot rather than a bullet glyph, so it aligns with the
            // calendar's own event markers.
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _announcementsList() {
    if (_announcements.isEmpty) {
      return _emptyNote('No announcements yet.');
    }

    final cs = Theme.of(context).colorScheme;
    // Flat rows, not cards inside a card: the nested surfaces added depth
    // without adding meaning, and ate the height that caused the clipping.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _announcements.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _announcements[i]['title']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_announcements[i]['from']} • ${_announcements[i]['time']}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// App shell. Every tab lives inside this one Scaffold, so the bottom bar
  /// is always present. Chat, Search and Settings used to be pushed as new
  /// routes, which covered the bar completely — that is why it vanished on
  /// those three tabs and stayed on Home and Calendar.
  ///
  /// IndexedStack keeps each tab alive, so scroll position and loaded data
  /// survive switching away and back, the way they do in Instagram.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _homeTab(showNotifications: true),
          const ChatListPage(),
          _homeTab(showNotifications: false),
          const SearchPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  /// Home and Calendar are the same surface; Calendar simply drops the
  /// notifications band to give the month grid the full height.
  Widget _homeTab({required bool showNotifications}) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _topBar(showNotifications: showNotifications),
      body: NeonBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: _groupsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final groupDocs = snapshot.data?.docs ?? [];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _syncGroups(groupDocs);
              }
            });

            return _buildHomeBody(
              groupDocs: groupDocs,
              showNotifications: showNotifications,
              isInitialLoading:
                  snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData,
            );
          },
        ),
      ),
    );
  }

  /// Instagram's top bar shape: wordmark hard left, actions hard right,
  /// nothing centred and no back affordance. The actions are real
  /// destinations rather than decoration — the bar was bare because it had
  /// a title and nothing else.
  PreferredSizeWidget _topBar({required bool showNotifications}) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      flexibleSpace: const GradientAppBarBackground(),
      title: Row(
        children: [
          const UnityLogo(size: 28),
          const SizedBox(width: 9),
          Text(
            showNotifications ? 'GroupApp' : 'Calendar',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
      actions: [
        _topBarAction(
          icon: Icons.add_box_outlined,
          tooltip: 'New group',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatListPage()),
          ),
        ),
        _topBarAction(
          icon: Icons.explore_outlined,
          tooltip: 'Discover clubs',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DiscoverPage()),
          ),
        ),
        _topBarAction(
          icon: Icons.qr_code_2,
          tooltip: 'My check-in code',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyCheckInCodePage()),
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _topBarAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 25),
      tooltip: tooltip,
      // Instagram's icons sit closer together than Material's default
      // 48dp slots, while staying above the 44dp touch floor.
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: VisualDensity.compact,
      splashRadius: 22,
      onPressed: onPressed,
    );
  }

  Widget _bottomNav() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: AppColors.cyan,
        unselectedItemColor: cs.onSurfaceVariant,
        // Icon-only, like Instagram: the labels were the only thing
        // distinguishing the tabs and they crowded a five-item bar.
        showSelectedLabels: false,
        showUnselectedLabels: false,
        iconSize: 26,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
            tooltip: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
            tooltip: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Calendar',
            tooltip: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
            tooltip: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
