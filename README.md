# Supermarket Ops · Staff mobile

Flutter app for the **STAFF** role (FA26SE103 / GFA26SE39). It covers the staff side of
**Mainflow 2** on the 10/10/2026 baseline (OperationalEvent → ResponsePolicy → Task offer /
qualified Incident, plus confirmed StaffReports):

- Sign in (real backend `POST /api/auth/login`, `GET /api/auth/me`; staff accounts only)
- My shifts, check-in (offers only reach checked-in staff) and **shift swaps** (MF-04): pick an
  eligible colleague to **swap** or **cover**, the colleague accepts or declines, then the Manager
  approves; requests received from colleagues are answered under Shifts → Swap requests
- Task offers with three responses: **Handle now**, **Accept and handle later** (planned start,
  overdue when missed) and **Cannot handle** (reason required); first acceptance wins; re-offer
  countdown (60 s × 3, then the Operator assigns)
- My tasks (Accepted / In progress / Done) with task origin (event, incident, staff report,
  Operator) and **Start now** for deferred tasks
- Report an issue by text, **voice** (on-device speech-to-text, no audio stored) or photo → AI
  draft → confirm as a **routine request** (becomes a Task) or a **potential incident** (goes
  through Incident qualification)
- Notifications, light and dark theme from the shared Figma "Theme" tokens

Evidence capture, verification and rework (MF-03) are not in this increment.

## Data sources

| Area | Source |
|---|---|
| Sign-in | Backend API. `--dart-define=MOCK_AUTH=true` signs in offline (password `staff123`). |
| Shifts, check-in, swaps, task offers, tasks, notifications | **Backend API** (`lib/data/http_operations_repository.dart`, routes in the Back-End `docs/API.md`, MF-02 and MF-04). There is no push channel yet (FCM is not built), so offers, tasks, eligibility and notifications are polled every 10 s, shifts and swaps every 30 s; pull to refresh on My shifts and Swap requests. |
| Phone notifications | **Local notifications** (`flutter_local_notifications`, `lib/core/device_notifications.dart`) while the app runs in the background: channel *Task offers* (heads-up, re-alerts on each re-offer and on CRITICAL, removed when the offer closes), *Task updates* and *Shifts and swaps*. Tapping one opens its screen. Nothing is shown while the app is in front, and nothing arrives once the app is closed: that needs FCM push, which the backend does not have yet. Android 13+ asks for the permission on first sign-in. |
| Staff reports | **In-app only.** The backend has no StaffReport API yet: the AI draft runs in the app and the receipt says *Preview only: not sent*. |
| Everything above, offline | `--dart-define=DEMO_OPS=true` (or `MOCK_AUTH=true`) runs the **in-app demo backend** (`lib/data/demo_operations_repository.dart`). |

The demo backend follows the 40 BRs in Report 3 and the 10/10/2026 PROJECT_CONTEXT
(eligibility, 2-task limit, first-accept-wins, 60 s × 3 re-offer and escalation, routine vs
qualified reports, colleague-then-Manager swaps) and the backend's 11/10/2026 OperationalEvent
episodes. **Me → Demo tools** raises an AI event task (rotating `LONG_QUEUE`,
`CHECKOUT_CAPACITY`, `CONGESTION`, `EXCESSIVE_WAIT`), an offer someone else accepts first,
escalates the latest WARNING event to CRITICAL (the same offer or task is updated), clears the
latest event (an open offer is withdrawn, an accepted task stays — provisional, see open point 5
in the contract), finishes active tasks, moves the latest swap request one step (the colleague
answers, then the Manager decides) and receives a swap request from a colleague. After check-in
the first offer arrives on its own after about 6 seconds.

## Run

```bash
flutter pub get
# Android emulator + local backend on the host (http://localhost:5080)
flutter run
# Physical phone on the same Wi-Fi as the backend
flutter run --dart-define=API_URL=http://192.168.1.10:5080
# Shared Dev API (writes to the team's Dev database; sign in with a STAFF account)
flutter run --dart-define=API_URL=https://supermarket-api-dev.kitsuracloud.com
# Real sign-in, demo data for shifts and tasks
flutter run --dart-define=DEMO_OPS=true
# No backend at all
flutter run --dart-define=MOCK_AUTH=true
```

A Staff member only sees shifts a Manager has **published** (`POST /api/schedule/publish`), and
only shifts more than 24 hours away can be swapped.

Debug builds allow plain HTTP for the local backend (`android/app/src/debug/AndroidManifest.xml`).
Release builds need HTTPS.

## Check

```bash
flutter analyze
flutter test
```

On Windows the analyzer can crash when the project path contains non-ASCII characters
(e.g. `Đồ án`). Run `flutter analyze` from a junction or a copy with an ASCII-only path.

## Structure

```
lib/
  core/        config, theme tokens (app_colors.dart), Dio client, router
  data/        models, OperationsRepository contract, HTTP and demo backends, Riverpod providers
  features/
    auth/      sign in, signing-in steps, session expired
    shifts/    my shifts, check-in, checked in; swaps: choose a colleague, progress, inbox
    alerts/    task offer sheet (3 responses), offers & notifications
    tasks/     my tasks, task detail
    report/    describe (text/voice/photo) → review AI draft → submitted; voice input
    me/        profile, demo tools, sign out
  shared/      widgets and formatting
test/          BR rules (fake time), auth controller, HTTP mapping (fake Dio adapter), whole-app flows
```
