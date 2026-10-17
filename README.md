# GroupApp (Flutter + Firebase)

GroupApp is a Flutter app for student groups/clubs with authentication, group chat, direct messages, calendar events, club discovery, personalized recommendations, and AI support chat.

## Current Status

This README reflects the current implementation in this repository.

## Core Features

- Firebase email/password authentication (login + register)
- Auth-gated routing (`AuthPage` when signed out, `HomePage` when signed in)
- Group chat system
- Create group with:
  - public/private mode
  - who-can-post setting (all/admins)
  - theme color + icon
  - overview text
  - banner image
  - keyword tags
- Join groups by 6-character join code
- Join public groups directly from Discover/Search
- Admin controls in group settings:
  - edit visibility/posting permissions/theme
  - manage admins
  - edit group keywords
- Direct messages between users
- Group calendar events + home calendar aggregation/filtering
- Student-first home experience with upcoming events and a direct path to club discovery
- Notifications panel on Home (latest group + DM activity)
- Discover page with newcomer guidance, clearly labeled sample club ideas, and live Firestore clubs
- Search page with keyword-aware matching and ranking
- Recommendation system:
  - user interest preferences are stored
  - clubs with matching keywords are ranked first
  - cards display why recommended (matched keyword chip)
- User Settings:
  - profile picture upload
  - first/last name editing
  - dark mode toggle
  - AI support entry
  - edit interest preferences
- First-run interests onboarding popup after sign-in
- AI support chat service with 3 backend modes:
  - direct Gemini API (demo)
  - Cloud Function (`supportChat`)
  - local scripted fallback

## Interests and Club Keywords

- User interests are saved in `users/{uid}`:
  - `interests: List<String>`
  - `interestsOnboardingSeen: bool`
- Group keywords are saved in `groups/{groupId}`:
  - `keywords: List<String>`
- Search and recommendations use these fields to personalize ordering.

## Key Files

- `lib/main.dart` - app bootstrap, Firebase init, auth-state routing
- `lib/Pages/home_page.dart` - home dashboard + onboarding trigger
- `lib/Pages/chat_list_page.dart` - group list + create/join dialogs
- `lib/Pages/chat_room_page.dart` - group chat + group settings/admin controls
- `lib/Pages/search_page.dart` - keyword-aware search + personalized recommendations
- `lib/Pages/discover_page.dart` - discover cards and reusable `ClubCard`
- `lib/Pages/settings_page.dart` - profile/settings/preferences editor
- `lib/components/interests_picker_dialog.dart` - onboarding/preferences popup UI
- `lib/data/interests_catalog.dart` - canonical interest list
- `lib/services/chat_service.dart` - Firestore/Storage group, DM, profile, preference APIs
- `lib/services/auth_service.dart` - authentication service
- `lib/services/ai_service.dart` - AI response logic and backend switching

## Dependencies (from `pubspec.yaml`)

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_storage`
- `cloud_functions`
- `table_calendar`
- `image_picker`
- `cached_network_image`
- `google_fonts`
- `http`

## Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Configure Firebase (already scaffolded in repo):
- Android: `android/app/google-services.json`
- iOS/macOS: `GoogleService-Info.plist`
- Generated options: `lib/firebase_options.dart`

3. Run:

```bash
flutter run
```

## AI Key Setup (Direct Gemini Demo Mode)

To enable direct Gemini replies, pass a key at build/run time:

```bash
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY_HERE
```

Without this optional key, the app still builds and runs, but AI support replies
that the feature is not configured. For public releases, use the Cloud Function
backend instead of embedding a Gemini key in the app.

## Data Notes

- Firestore collections used:
  - `users`
  - `groups`
  - `directMessages`
- Group subcollections:
  - `messages`
  - `events`
- Storage paths used:
  - `profile_pictures/`
  - `group_banners/`
  - `chat_images/`

## Known Development Notes

- After major widget refactors, prefer full restart over hot reload if emulator shows stale widget lookup errors.
- Some UI behavior is demo-seeded (for example demo clubs and example notifications).

## Last Updated

2026-07-10
