import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';

/// A single message in the support conversation.
class AiMessage {
  final String role; // 'user' or 'assistant'
  final String content;

  const AiMessage({required this.role, required this.content});

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// How the support chat gets its replies.
enum AiBackend {
  /// Call Google Gemini directly from the app (demo only — key is embedded).
  directGemini,

  /// Call the deployed `supportChat` Cloud Function (production, key hidden).
  cloudFunction,

  /// On-device scripted answers (no network, no key).
  scripted,
}

/// Support-chat backend.
///
/// This app is a demo, so [backend] defaults to [AiBackend.directGemini], which
/// calls Google Gemini straight from the app using [_apiKey] below.
///
/// ⚠️ SECURITY: an API key shipped inside the app can be extracted from the
/// build. This is acceptable ONLY for a local demo. Before releasing publicly,
/// switch [backend] to [AiBackend.cloudFunction] and keep the key server-side.
class AiService {
  static const AiBackend backend = AiBackend.directGemini;

  /// Build-time override, passed by CI as
  /// `--dart-define=GEMINI_API_KEY=...`. Empty on an ordinary local build.
  static const String _definedKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  /// The key actually used. A `--dart-define` wins when one was passed;
  /// A missing key does not prevent the app from building; AI replies explain
  /// that the feature needs configuration.
  static const String _apiKey = _definedKey;

  static const String _model = 'gemini-2.5-flash';

  static const String _systemPrompt =
      "You are Jarvis, the friendly AI assistant built into GroupApp, a mobile "
      "app for student clubs and groups. Members can summon you in any group "
      "chat by typing \"@jarvis\" followed by a question.\n\n"
      "GroupApp's features:\n"
      "- Group chats: users create or join group chats. Public groups can be "
      "joined with a 6-character join code, or discovered on the Discover page. "
      "Private groups require an invite.\n"
      "- Join codes: each group has a 6-character code. Share it so others can "
      "join. Find it via the group's info (i) button.\n"
      "- Direct messages: users can message each other one-on-one, including "
      "tapping \"Message\" next to a member in a group's info panel.\n"
      "- Calendar & events: group admins/owners add events (title, description, "
      "date, time) that appear on every member's home calendar. Filter which "
      "groups show via the calendar's tune icon.\n"
      "- Announcements & notifications appear on the home page.\n"
      "- Roles: a group has an owner (creator) and admins. Admins change group "
      "settings (public/private, who can post, theme color/icon) and manage the "
      "admin list. \"Who can post\" can be all members or admins only.\n"
      "- Profile: users set a first/last name and profile picture in Settings. "
      "Settings also has a Dark Mode toggle.\n\n"
      "Guidelines:\n"
      "- Be concise, warm, and practical. Give step-by-step instructions.\n"
      "- Only answer questions about GroupApp; gently redirect anything else.\n"
      "- If you don't know an app-specific detail, say so rather than inventing "
      "features.\n"
      "- Never ask for or handle passwords, join codes, or personal data.";

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  /// Sends the full conversation history and returns the assistant's reply.
  Future<String> sendMessage(List<AiMessage> history) async {
    switch (backend) {
      case AiBackend.directGemini:
        return _directGeminiReply(history);
      case AiBackend.cloudFunction:
        return _cloudReply(history);
      case AiBackend.scripted:
        return _scriptedReply(history);
    }
  }

  /// Answers an in-chat "@jarvis" question. [recentMessages] is optional recent
  /// group chat context as {sender, text} maps (oldest first) so Jarvis can
  /// respond in context.
  Future<String> askJarvis(
    String question, {
    List<Map<String, String>> recentMessages = const [],
  }) async {
    final buffer = StringBuffer();
    if (recentMessages.isNotEmpty) {
      buffer.writeln('Here is the recent chat for context:');
      for (final m in recentMessages) {
        final name = (m['sender'] ?? 'user').split('@').first;
        buffer.writeln('$name: ${m['text']}');
      }
      buffer.writeln('');
    }
    buffer.writeln('A group member asked Jarvis: "$question"');
    buffer.writeln('Reply helpfully and concisely as Jarvis.');

    return sendMessage([AiMessage(role: 'user', content: buffer.toString())]);
  }

  // ---------------------------------------------------------------------------
  // Direct Gemini call (demo only — key embedded in the app)
  // ---------------------------------------------------------------------------

  Future<String> _directGeminiReply(List<AiMessage> history) async {
    if (_apiKey.isEmpty) {
      return "The AI assistant isn't configured. The Gemini API key is supplied "
          "at build time via --dart-define=GEMINI_API_KEY=... (set as the "
          "GEMINI_API_KEY variable in Codemagic). In the meantime, I can't answer.";
    }

    // Gemini uses `contents` with role 'user' or 'model' and `parts: [{text}]`.
    final contents = history
        .map(
          (m) => {
            'role': m.isUser ? 'user' : 'model',
            'parts': [
              {'text': m.content},
            ],
          },
        )
        .toList();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$_model:generateContent?key=$_apiKey',
    );

    final response = await http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt},
          ],
        },
        'contents': contents,
        'generationConfig': {'maxOutputTokens': 1024},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Empty response from Gemini');
    }

    final content = (candidates.first as Map)['content'] as Map?;
    final parts = content?['parts'] as List<dynamic>?;
    final text = parts
        ?.map((p) => (p as Map)['text'] as String? ?? '')
        .join()
        .trim();

    if (text == null || text.isEmpty) {
      throw Exception('Empty response from Gemini');
    }
    return text;
  }

  // ---------------------------------------------------------------------------
  // Cloud Function (production — key stays server-side)
  // ---------------------------------------------------------------------------

  Future<String> _cloudReply(List<AiMessage> history) async {
    final callable = _functions.httpsCallable('supportChat');
    final result = await callable.call<Map<String, dynamic>>({
      'messages': history.map((m) => m.toJson()).toList(),
    });

    final reply = result.data['reply'] as String?;
    if (reply == null || reply.isEmpty) {
      throw Exception('Empty response from assistant');
    }
    return reply;
  }

  // ---------------------------------------------------------------------------
  // Scripted fallback (no network, no key)
  // ---------------------------------------------------------------------------

  Future<String> _scriptedReply(List<AiMessage> history) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final lastUser = history.lastWhere(
      (m) => m.isUser,
      orElse: () => const AiMessage(role: 'user', content: ''),
    );
    final q = lastUser.content.toLowerCase();
    for (final entry in _knowledge) {
      if (entry.keywords.any(q.contains)) return entry.answer;
    }
    return "I can help with GroupApp features like creating and joining groups, "
        "join codes, direct messages, the calendar, admin settings, and your "
        "profile. Try \"How do I join a group?\"";
  }

  static final List<_QA> _knowledge = [
    _QA(
      keywords: ['create', 'make', 'new group'],
      answer:
          "To create a group: open Messages, tap the blue + button, enter a "
          "name and details, then Create. You'll get a 6-character join code.",
    ),
    _QA(
      keywords: ['join', 'code'],
      answer:
          "To join a group: on the Messages page tap the login (arrow) button "
          "and enter the 6-character join code someone shared with you.",
    ),
    _QA(
      keywords: ['calendar', 'event'],
      answer:
          "Group owners add events from the calendar icon in the group chat — "
          "enter a title, date, and time. It appears on every member's home "
          "calendar.",
    ),
  ];
}

class _QA {
  final List<String> keywords;
  final String answer;
  const _QA({required this.keywords, required this.answer});
}
