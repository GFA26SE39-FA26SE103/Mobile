# Staff mobile API — proposed contract (10/10/2026 baseline)

> **Superseded for implemented routes (20/10/2026).** Shifts, check-in, eligibility, task offers,
> tasks, notifications and SWAP/COVER requests now exist on the backend and the app calls them
> through `lib/data/http_operations_repository.dart`; the routes and error codes are in Back-End
> `docs/API.md` (MF-02 staff tasks, MF-04 swaps), which wins where this file differs. Swaps follow
> A → colleague accepts → Manager approves, not the Operator flow below. Still open here:
> StaffReport (the app keeps it in-app) and push (the app polls).

Status: **proposal**, aligned with Back-End `AGENTS.md` / `docs/PROJECT_CONTEXT.md` (10/10/2026
synchronization, provisional ERD v4, 11/10/2026 OperationalEvent episodes on Database V2) and
Reports 1–3 (BR-01…BR-40). The backend has no Task,
StaffReport or shift API yet; the app runs these flows on `DemoOperationsRepository`. When the
endpoints exist, add an `HttpOperationsRepository` implementing `lib/data/operations_repository.dart`
and switch `operationsRepositoryProvider`. Names below are what the screens need, not a schema;
the physical model follows ERD v4.

Conventions match MF-01: JWT bearer, camelCase JSON, UUID ids, ISO 8601 UTC, ProblemDetails with
`code` and `detail`. Every route requires role `STAFF` and only returns the caller's own data.

## Target chain the app reflects

```
Measurement → MonitoringRule → OperationalEvent → ResponsePolicy → ResponsePolicyAction
  → Notification / Recommendation / Operational Task / qualifying Incident → Staff handling
StaffReport (confirmed) → routine Task, or Incident qualification → corrective Task(s)
```

- A threshold breach or CRITICAL priority does **not** create an Incident by itself.
- Since 11/10/2026 the backend stores an OperationalEvent as one **episode** per Camera + Zone +
  OperationalEventType (`LONG_QUEUE`, `EXCESSIVE_WAIT`, `CONGESTION`, `CHECKOUT_CAPACITY`): status
  `ACTIVE` while the breach lasts, `priority` only rises (WARNING → CRITICAL) on the same row, and
  sustained recovery sets `CLEARED`. So one event yields at most one task offer; a priority rise
  updates that offer instead of creating another.
- A Task has exactly one origin: `OPERATIONAL_EVENT`, `INCIDENT`, `STAFF_REPORT`, `MANUAL`.
- No mandatory Operator pre-dispatch review (BR-15, BR-16); the Operator can intervene.

## Rules the backend must enforce

| Rule | Behaviour |
|---|---|
| BR-19, BR-35 | Offers go to staff who are on shift, checked in and assigned to the zone |
| BR-23 | Active-task limit (2 in the demo) |
| BR-21 | First valid acceptance wins atomically; others get `409 TASK_ALREADY_TAKEN` and the offer is withdrawn |
| BR-22 | Re-notify every 60 s up to the configured limit (3), then Operator assigns manually |
| BR-20 | No eligible staff → adjacent zone + Operator (**ZoneAdjacency use still unconfirmed** in PROJECT_CONTEXT) |
| BR-24 | `CANNOT_HANDLE` requires a reason; it is a response, not evidence rejection |
| Task response semantics | `HANDLE_NOW` = accept + start; `HANDLE_LATER` = accept with planned start; overdue when not started by then |
| BR-16, BR-17 | Reports are confirmed by the reporter; routine → optional Task; potential Incident → qualification |
| BR-34 + 05/10 delta | Swap only for shifts not yet started; Staff requests, Operator approves after the system proposes valid candidates |
| Check-in | Opens 15 min before shift start |

## Endpoints

| Method & path | Body | Response | Errors |
|---|---|---|---|
| `GET /api/me/shifts?from=&to=` | — | `Shift[]` | — |
| `POST /api/me/shifts/{shiftId}/check-in` | — | `Shift` | `422 CHECK_IN_TOO_EARLY` (`opensAt`), `409 SHIFT_ENDED` |
| `GET /api/me/eligibility` | — | `{ checkedIn, activeTasks, zoneId, zoneName }` | — |
| `POST /api/me/devices` | `{ fcmToken, platform }` | `204` | — |
| `GET /api/me/task-offers?status=OPEN` | — | `TaskOffer[]` | — |
| `POST /api/task-offers/{offerId}/respond` | `{ response: HANDLE_NOW \| HANDLE_LATER \| CANNOT_HANDLE, plannedStartAt?, reason? }` | `StaffTask` (or `204` for CANNOT_HANDLE) | `409 TASK_ALREADY_TAKEN` (`takenBy`, `takenAt`), `409 WORKLOAD_LIMIT`, `409 OFFER_CLOSED`, `422 REASON_REQUIRED` |
| `GET /api/me/tasks?status=ACCEPTED\|IN_PROGRESS\|DONE` | — | `StaffTask[]` | — |
| `GET /api/tasks/{taskId}` | — | `StaffTask` | `404` |
| `POST /api/tasks/{taskId}/start` | — | `StaffTask` | `409 TASK_NOT_ACCEPTED` |
| `GET /api/me/notifications` | — | `AppNotification[]` | — |
| `POST /api/me/notifications/read-all` | — | `204` | — |
| `POST /api/staff-reports/attachments` | multipart `file` (JPEG/PNG ≤ 10 MB) | `{ attachmentId }` | `422 ATTACHMENT_INVALID` |
| `POST /api/staff-reports/extract` | `{ note, attachmentIds[], fromVoice }` | `ReportDraft` + `aiFields[]` | `503 AI_UNAVAILABLE` |
| `POST /api/staff-reports` | confirmed `ReportDraft` incl. `kind: ROUTINE_REQUEST \| POTENTIAL_INCIDENT` | `ReportReceipt` | `422` validation |
| `GET /api/me/shift-swaps` | — | `ShiftSwapRequest[]` | — |
| `POST /api/me/shifts/{shiftId}/swap-requests` | `{ reason, note }` | `ShiftSwapRequest` | `409 SHIFT_STARTED`, `409 SWAP_PENDING`, `422 NOTE_REQUIRED` |

Voice reports are transcribed on the device and sent as text (`fromVoice: true`). Durable voice
or image storage and retention remain an open decision in PROJECT_CONTEXT (StaffReport media).

## Realtime

- **Foreground:** SignalR hub `/hubs/staff`, events `offer.created`, `offer.updated` (attempt,
  nextAlertAt, priority/measurement when the episode escalates), `offer.closed` (`takenBy`, or
  reason `EVENT_CLEARED`), `task.updated` (priority, `eventClearedAt`), `swap.decided`.
- **Background / locked screen:** FCM data message `{ type: "task-offer", offerId }`; the app
  fetches the offer and opens the offer sheet. Needs a device-token table (not in ERD v4 as listed).

## Payload shapes

Field names mirror `lib/data/models.dart`:

```jsonc
// TaskOffer (eventTypeCode only for OPERATIONAL_EVENT origin)
{ "offerId": "uuid", "origin": "OPERATIONAL_EVENT", "sourceCode": "EVT-1043", "eventTypeCode": "LONG_QUEUE",
  "title": "Long queue at checkout", "priority": "CRITICAL", "zoneName": "Zone B · Checkout",
  "location": "Checkout 3", "measurement": "11 people waiting · 6 min",
  "instructions": "Open 1 more counter and redirect the queue", "createdAt": "…",
  "recipients": 3, "attempt": 1, "nextAlertAt": "…", "status": "OPEN" }

// StaffTask
{ "taskId": "uuid", "origin": "OPERATIONAL_EVENT", "sourceCode": "EVT-1043", "title": "…",
  "priority": "CRITICAL", "zoneName": "…", "location": "…", "instructions": "…",
  "createdAt": "…", "acceptedAt": "…", "status": "ACCEPTED",
  "plannedStartAt": "…", "startedAt": null, "cameraCode": "CAM-03",
  "eventTypeCode": "LONG_QUEUE", "raisedFrom": "WARNING", "eventClearedAt": null }

// ReportReceipt
{ "reportCode": "RPT-0241", "outcome": "INCIDENT_QUALIFIED", "incidentCode": "INC-1013",
  "title": "…", "location": "…", "zoneName": "…", "offeredTo": 2, "submittedAt": "…", "edited": true }
```

## Open points to confirm with the team

1. Whether `ZoneAdjacency` is used for dispatch (BR-20 says yes; PROJECT_CONTEXT says unconfirmed).
2. Who approves swaps: AGENTS/PROJECT_CONTEXT say the Operator; Report 3 BR-34 says only the
   Manager modifies future shift assignments.
3. Report 3 task states (3.7.3) do not yet include the deferred "Accept and Handle Later" state.
4. The Incident-qualification policy for staff reports (the demo opens an Incident for Medium/High
   severity potential incidents; the real policy is configured server-side).
5. What happens to an open offer when its OperationalEvent episode is `CLEARED` before anyone
   accepts (withdraw it with an `offer.closed` reason, or keep it so staff still check the area),
   and to an accepted task whose event clears before it is started. The demo currently withdraws
   the open offer (`OfferStatus.eventCleared`) and keeps accepted tasks, marked "Event cleared",
   so the staff member checks the area and finishes them.
