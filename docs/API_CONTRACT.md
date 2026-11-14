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
| Evidence | `GET /api/tasks/{taskId}/evidence`; `POST /api/tasks/{taskId}/evidence` (multipart `file` + `type` BEFORE_PHOTO/AFTER_PHOTO); `DELETE /api/tasks/{taskId}/evidence/{evidenceId}`; photo bytes at the returned `imageUrl` (JWT) |
| Submit | `POST /api/tasks/{taskId}/submit` `{ note }` → IN_PROGRESS to SUBMITTED |
| Swaps | `GET /api/me/swap-requests`, `GET /api/me/shifts/{id}/swap-candidates?type=SWAP\|COVER`, `POST /api/swap-requests`, `POST /api/swap-requests/{id}/respond`, `POST /api/swap-requests/{id}/cancel` |

Respond bodies:

```json
{"response":"HANDLE_NOW","plannedStartAt":null,"reason":null}
{"response":"HANDLE_LATER","plannedStartAt":"2026-10-25T06:30:00Z","reason":null}
{"response":"CANNOT_HANDLE","plannedStartAt":null,"reason":"BUSY"}
```

`HANDLE_NOW` → task `IN_PROGRESS`; `HANDLE_LATER` → `ACCEPTED` with a planned start that must be in
the future and before `shiftEndsAt` (the app only offers delays inside the shift);
`CANNOT_HANDLE` needs a reason and creates no task for the caller. The app reports success only
after the server answers. Repeating an accepted response (e.g. after a timeout) returns the same
task instead of `OFFER_CLOSED`.

`GET /api/me/shifts` also returns `CANCELLED` assignments; the app leaves them out of My shifts
(check-in answers `SHIFT_CANCELLED`). Draft assignments are never returned.

Errors the app handles: `TASK_ALREADY_TAKEN` (detail names who and when), `OFFER_CLOSED`,
`WORKLOAD_LIMIT`, `CHECK_IN_TOO_EARLY`. Others (`NOT_ON_SHIFT`, `INVALID_PLANNED_START`,
`REASON_REQUIRED`, `SHIFT_ENDED`, `SHIFT_CANCELLED`, `TASK_SCHEMA_NOT_READY`, swap rule codes) are
shown with the server's message. A failed call never shows as success, and the real mode never
falls back to demo data.

## States

- Task: `ACCEPTED`, `IN_PROGRESS`, `SUBMITTED` (waiting for the Operator to verify), `VERIFIED`
  (confirmed done), `CANCELLED`. My tasks shows Accepted / In progress / Finished.
  `eventClearedAt` means the source event recovered; it is not the completion time.
- Offer (TaskOffer V7, Back-End `feature/after-review-backend-sync`): `PENDING` (open),
  `ACCEPTED`, `DECLINED` (the app sends `BUSY`, `UNAVAILABLE`, `NOT_QUALIFIED` or `OTHER` as
  `reason`, stored as `decline_reason_code`), `EXPIRED` (no response in time; not a decline),
  `CANCELLED` with `closedReason` `TAKEN_BY_OTHER`, `EVENT_CLEARED` or `MANUALLY_ASSIGNED`. A
  cancelled offer is not assumed to be taken by someone else. The offer view still returns
  `attempt`, `maxAttempts` and `nextAlertAt`, which is null on the last round. It does not return
  `expiresAt`, `waveNumber` or `dispatchScope`; the app reads them only if the backend adds them.
- Swap: `PENDING_PEER` → `PENDING_MANAGER` → `APPROVED` / `REJECTED`, or `DECLINED_BY_PEER`,
  `CANCELLED`, `EXPIRED`. `expiresAt` comes from the server: 24 h before the earliest affected
  shift. Only the Manager's approval changes assignments.

## Delivery

There is no push channel (no FCM, no SignalR). While the app is in front it polls offers, tasks,
eligibility and notifications every 5 s and shifts and swaps every 30 s; polling stops in the
background and everything reloads on resume. An offer sheet opens again only when the offer id,
attempt or priority changes. The countdown uses the server's `nextAlertAt` (retry interval is a
`SystemSetting`, 10 s in the MF-02 demo); it is null on the last round, which the app shows as
"Last offer" without inventing a time. Signing out disposes the repository, its timers and cached data.

## Completion (MF-03)

From a task in progress, **Complete task** opens the completion screen with optional before/after
photo slots (Review 2, BR-34). An Incident corrective task needs an after photo; without one, the app
asks for a completion note and **Why is there no after photo?**, sent as `missingPhotoReason` (at most
1000 characters). With an after photo the Incident note is optional. Every other task needs a note and
never sends `missingPhotoReason`. Each photo uploads as soon as it is picked; a failed upload keeps the
picture and offers **Retry upload**, and uploading the same kind again replaces the draft on the server.

Task, offer and evidence views carry `verificationMode`. The app shows it as **Automatic check** (AUTO:
verified from the camera metric once the event clears; missing data moves it to an Operator) or
**Operator review** (MANUAL). A submit that comes back `VERIFIED` is shown as verified automatically.
`rejectionCount` is shown on the task detail. The first rejection returns the task as "Rework needed";
the next one takes it away and it is reassigned (BR-36). Notifications `TASK_VERIFIED` and
`TASK_AUTO_VERIFIED` show as verified, `TASK_REJECTED` as returned. Server errors such as
`EVIDENCE_REQUIRED`, `MISSING_PHOTO_REASON_REQUIRED`, `MISSING_PHOTO_REASON_NOT_APPLICABLE` or
`TASK_NOT_IN_PROGRESS` are shown as sent.

Reports carry no severity: the app neither shows nor sends one (V7 removed Incident severity).

## Not on the backend yet

- StaffReport extraction/confirmation: the app keeps reports on the phone and marks the receipt
  "Preview only: not sent".
- FCM device registration and push.
- Store, floor and teammate names for a shift; the app leaves them out rather than inventing them.

Demo mode (`--dart-define=DEMO_OPS=true`, or `MOCK_AUTH=true`) runs everything on
`DemoOperationsRepository` and shows a DEMO DATA ribbon.
