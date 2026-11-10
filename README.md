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
- My tasks (Accepted / In progress / Finished) with task origin (event, incident, staff report,
  Operator) and **Start now** for deferred tasks; Finished separates *Waiting for verification*
  (SUBMITTED), *Verified* and *Cancelled*
- Report an issue by text, photo, on-device dictation, or recorded **voice note** → Backend AI
  suggestion → Staff review → confirm as a **routine request** (Task) or a **potential incident**
  (Incident with Staff-confirmed corrective Tasks). Recorded audio is sent to Backend for transcription
  and stored with the confirmed report; AI drafts are not saved server-side.
- Notifications, light and dark theme from the shared Figma "Theme" tokens

Evidence capture, verification and rework (MF-03) are not in this increment.

## Data sources

| Area | Source |
|---|---|
| Sign-in | Backend API. `--dart-define=MOCK_AUTH=true` signs in offline (password `staff123`). |
| Shifts, check-in, swaps, task offers, tasks, notifications | **Backend API** (`lib/data/http_operations_repository.dart`, routes in the Back-End `docs/API.md`, MF-02 and MF-04). There is no push channel yet (FCM is not built), so while the app is in front offers, tasks, eligibility and notifications are polled every 5 s, shifts and swaps every 30 s; polling stops in the background and everything reloads on resume. Pull to refresh on My shifts and Swap requests. |
| Phone notifications | **Local notifications** (`flutter_local_notifications`, `lib/core/device_notifications.dart`): channel *Task offers* (heads-up, re-alerts on each re-offer and on CRITICAL, removed when the offer closes), *Task updates* and *Shifts and swaps*. Tapping one opens its screen. They are shown only for changes the app learns about after it leaves the front; since polling stops in the background, the shade stays quiet until FCM push exists on the backend. Android 13+ asks for the permission on first sign-in. |
| Staff reports | Backend `GET /api/staff-reports/*` catalogs and `POST /api/staff-reports/draft` for opt-in AI suggestions; `POST /api/staff-reports` saves the Staff-confirmed report and optional photos/voice note. If AI is unavailable, Staff can fill the review manually. Drafts live only in the current app session, not on the server. |
| Everything above, offline | `--dart-define=DEMO_OPS=true` (or `MOCK_AUTH=true`) runs the **in-app demo backend** (`lib/data/demo_operations_repository.dart`). |

The demo backend follows the 40 BRs in Report 3 and the 10/10/2026 PROJECT_CONTEXT
(eligibility, 2-task limit, first-accept-wins, 60 s × 3 re-offer and escalation, routine vs
qualified reports, colleague-then-Manager swaps) and the backend's 11/10/2026 OperationalEvent
episodes. **Me → Demo tools** raises an AI event task (rotating `LONG_QUEUE`,
`CHECKOUT_CAPACITY`, `CONGESTION`, `EXCESSIVE_WAIT`), an offer someone else accepts first,
escalates the latest WARNING event to CRITICAL (the same offer or task is updated), clears the
latest event (an open offer is withdrawn, an accepted task stays — provisional, see open point 5
in the contract), submits active tasks (they wait for verification), moves the latest swap request one step (the colleague
answers, then the Manager decides) and receives a swap request from a colleague. After check-in
the first offer arrives on its own after about 6 seconds.

## Run

```bash
flutter pub get
# Shared Dev API, the default (writes to the team's Dev database; sign in with a STAFF account)
flutter run
# Android emulator + local backend on the host (http://localhost:5080)
flutter run --dart-define=API_URL=http://10.0.2.2:5080
# Physical phone on the same Wi-Fi as the backend
flutter run --dart-define=API_URL=http://192.168.1.10:5080
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
