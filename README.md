# Supermarket Ops · Staff mobile

Flutter app for the **STAFF** role (FA26SE103 / GFA26SE39). It covers the staff side of
**Mainflow 2** on the 10/10/2026 baseline (OperationalEvent → ResponsePolicy → Task offer /
qualified Incident, plus confirmed StaffReports):

- Sign in (real backend `POST /api/auth/login`, `GET /api/auth/me`; staff accounts only)
- My shifts, check-in (offers only reach checked-in staff) and **shift swap requests** that the
  Operator approves
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
| Shifts, swaps, task offers, tasks, notifications, staff reports | **In-app demo backend** (`lib/data/demo_operations_repository.dart`). The backend has no Task / StaffReport / shift API yet; the proposed contract is in [docs/API_CONTRACT.md](docs/API_CONTRACT.md). |

The demo backend follows the 40 BRs in Report 3 and the 10/10/2026 PROJECT_CONTEXT
(eligibility, 2-task limit, first-accept-wins, 60 s × 3 re-offer and escalation, routine vs
qualified reports, Operator-approved swaps) and the backend's 11/10/2026 OperationalEvent
episodes. **Me → Demo tools** raises an AI event task (rotating `LONG_QUEUE`,
`CHECKOUT_CAPACITY`, `CONGESTION`, `EXCESSIVE_WAIT`), an offer someone else accepts first,
escalates the latest WARNING event to CRITICAL (the same offer or task is updated), clears the
latest event (an open offer is withdrawn, an accepted task stays — provisional, see open point 5
in the contract), finishes active tasks, and approves or declines the latest swap request as the
Operator. After check-in the first offer arrives on its own after about
6 seconds.

## Run

```bash
flutter pub get
# Android emulator + local backend on the host (http://localhost:5080)
flutter run
# Physical phone on the same Wi-Fi as the backend
flutter run --dart-define=API_URL=http://192.168.1.10:5080
# No backend at all
flutter run --dart-define=MOCK_AUTH=true
```

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
  data/        models, OperationsRepository contract, demo backend, Riverpod providers
  features/
    auth/      sign in, signing-in steps, session expired
    shifts/    my shifts, check-in, checked in, swap request
    alerts/    task offer sheet (3 responses), offers & notifications
    tasks/     my tasks, task detail
    report/    describe (text/voice/photo) → review AI draft → submitted; voice input
    me/        profile, demo tools, sign out
  shared/      widgets and formatting
test/          BR rules (fake time), auth controller, whole-app flows
```
