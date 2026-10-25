# Staff mobile API — what the app calls (25/10/2026)

The backend implements the MF-02 Staff-task subset and the MF-04 SWAP/COVER flow; the app calls
them through `lib/data/http_operations_repository.dart`. The authoritative DTOs are Back-End
`src/Supermarket.Application/StaffWorkContracts.cs` and the swap contracts, with routes and
validation in Back-End `docs/API.md`. Where this file and the backend differ, the backend wins.

Conventions: JWT bearer with role `STAFF`, camelCase JSON, UUID ids, ISO 8601 UTC (a time without
an offset is read as UTC), ProblemDetails with `code` and `detail`. Every route returns only the
caller's own data. `401` ends the session (Session expired screen); `403` is the wrong role.

## Flow the backend implements

```
AUTOMATIC CREATE_OPERATIONAL_TASK policy on an OperationalEvent
→ Task OFFERED to checked-in, on-shift Staff assigned to the target Zone
→ HANDLE_NOW / HANDLE_LATER / CANNOT_HANDLE; the first valid acceptance wins atomically
→ unaccepted offers are retried (SystemSetting, default 60 s × 3 attempts), then flagged for
  Operator assignment
```

An OperationalEvent never becomes an Incident. Model confidence only filters detections; it is
not a routing gate. No Operator pre-dispatch review.

## Endpoints

| Purpose | Route |
| --- | --- |
| My shifts | `GET /api/me/shifts?from=YYYY-MM-DD&to=YYYY-MM-DD` → `ShiftView[]` |
| Check in | `POST /api/me/shifts/{shiftAssignmentId}/check-in`, no body → `ShiftView` |
| Eligibility | `GET /api/me/eligibility` → `{ checkedIn, shiftAssignmentId, shiftEndsAt, activeTasks, maxActiveTasks, zones[] }` |
| Open offers | `GET /api/me/task-offers` |
| Offers incl. last 24 h outcomes | `GET /api/me/task-offers?status=ALL` (the app uses this) |
| Offer detail | `GET /api/task-offers/{offerId}` |
| Respond | `POST /api/task-offers/{offerId}/respond` → `{ response, task: StaffTaskView \| null }` |
| My tasks | `GET /api/me/tasks?status=ACCEPTED,IN_PROGRESS,SUBMITTED,VERIFIED,CANCELLED` |
| Task detail | `GET /api/tasks/{taskId}` |
| Start | `POST /api/tasks/{taskId}/start` → `StaffTaskView` |
| Inbox | `GET /api/me/notifications`; `POST /api/me/notifications/read-all` → `204` |
| Swaps | `GET /api/me/swap-requests`, `GET /api/me/shifts/{id}/swap-candidates?type=SWAP\|COVER`, `POST /api/swap-requests`, `POST /api/swap-requests/{id}/respond`, `POST /api/swap-requests/{id}/cancel` |

Respond bodies:

```json
{"response":"HANDLE_NOW","plannedStartAt":null,"reason":null}
{"response":"HANDLE_LATER","plannedStartAt":"2026-10-25T06:30:00Z","reason":null}
{"response":"CANNOT_HANDLE","plannedStartAt":null,"reason":"Busy with another task"}
```

`HANDLE_NOW` → task `IN_PROGRESS`; `HANDLE_LATER` → `ACCEPTED` with a planned start that must be in
the future and before `shiftEndsAt` (the app only offers delays inside the shift);
`CANNOT_HANDLE` needs a reason and creates no task for the caller. The app reports success only
after the server answers.

Errors the app handles: `TASK_ALREADY_TAKEN` (detail names who and when), `OFFER_CLOSED`,
`WORKLOAD_LIMIT`, `CHECK_IN_TOO_EARLY`. Others (`NOT_ON_SHIFT`, `INVALID_PLANNED_START`,
`REASON_REQUIRED`, `SHIFT_ENDED`, `SHIFT_CANCELLED`, `TASK_SCHEMA_NOT_READY`, swap rule codes) are
shown with the server's message. A failed call never shows as success, and the real mode never
falls back to demo data.

## States

- Task: `ACCEPTED`, `IN_PROGRESS`, `SUBMITTED` (waiting for the Operator to verify), `VERIFIED`
  (confirmed done), `CANCELLED`. My tasks shows Accepted / In progress / Finished.
  `eventClearedAt` means the source event recovered; it is not the completion time.
- Offer: `OFFERED` (open), `ACCEPTED`, `DECLINED`, `EXPIRED` (no acceptance; passed to the
  Operator), `WITHDRAWN` with `closedReason` `TAKEN_BY_OTHER`, `EVENT_CLEARED` or
  `MANUALLY_ASSIGNED`. A withdrawn offer is not assumed to be taken by someone else.
- Swap: `PENDING_PEER` → `PENDING_MANAGER` → `APPROVED` / `REJECTED`, or `DECLINED_BY_PEER`,
  `CANCELLED`, `EXPIRED`. `expiresAt` comes from the server: 24 h before the earliest affected
  shift. Only the Manager's approval changes assignments.

## Delivery

There is no push channel (no FCM, no SignalR). While the app is in front it polls offers, tasks,
eligibility and notifications every 5 s and shifts and swaps every 30 s; polling stops in the
background and everything reloads on resume. An offer sheet opens again only when the offer id,
attempt or priority changes. Signing out disposes the repository, its timers and cached data.

## Not on the backend yet

- Task completion evidence (upload/submit) and Operator verification. The app has no Done action
  in real mode; Demo tools are only in demo mode.
- StaffReport extraction/confirmation: the app keeps reports on the phone and marks the receipt
  "Preview only: not sent".
- FCM device registration and push.
- Store, floor and teammate names for a shift; the app leaves them out rather than inventing them.

Demo mode (`--dart-define=DEMO_OPS=true`, or `MOCK_AUTH=true`) runs everything on
`DemoOperationsRepository` and shows a DEMO DATA ribbon.
