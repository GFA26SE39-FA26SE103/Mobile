// Domain model for the Staff side of Mainflow 2, following the 10/10/2026 baseline:
// Measurement → OperationalEvent → ResponsePolicy → Task offer / qualified Incident,
// plus the separate confirmed StaffReport path.

/// Alert level shown to Staff: OperationalEvent/Task priority and Notification.Severity.
/// V7 has no Incident severity; this is not one.
enum Severity {
  critical('CRITICAL'),
  warning('WARNING'),
  info('INFO');

  const Severity(this.label);
  final String label;
}

/// Exactly one origin per Task (ERD v4 `Task.origin_type`).
enum TaskOrigin {
  operationalEvent('Operational event'),
  incident('Incident'),
  staffReport('Staff report'),
  manual('Assigned by Operator');

  const TaskOrigin(this.label);
  final String label;
}

class Shift {
  const Shift({
    required this.shiftId,
    required this.start,
    required this.end,
    required this.label,
    required this.zoneName,
    this.zoneDetail = '',
    this.zoneIds = const [],
    this.floorName = '',
    this.storeName = '',
    this.teammates = const [],
    this.checkedInAt,
    // Dart private named parameter: callers pass `checkInOpensAt:`.
    this._checkInOpensAt,
  });

  /// The ShiftAssignment id on the backend.
  final String shiftId;
  final DateTime start;
  final DateTime end;
  final String label;
  final String zoneName;

  /// Details the API does not return yet (counters, floor, store, teammates) are empty there.
  final String zoneDetail;
  final List<String> zoneIds;
  final String floorName;
  final String storeName;
  final List<String> teammates;
  final DateTime? checkedInAt;
  final DateTime? _checkInOpensAt;

  /// BR: check-in opens 15 minutes before the shift starts.
  static const checkInWindow = Duration(minutes: 15);
  DateTime get checkInOpensAt => _checkInOpensAt ?? start.subtract(checkInWindow);

  /// "Floor 1 · Counters 1–6", or empty when neither is known.
  String get placeDetail => [floorName, zoneDetail].where((s) => s.isNotEmpty).join(' · ');

  bool get isCheckedIn => checkedInAt != null;
  bool isActiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);
  bool isTodayAt(DateTime now) => start.year == now.year && start.month == now.month && start.day == now.day;

  /// BR-34: a shift cannot be changed after it has started.
  bool canRequestSwapAt(DateTime now) => now.isBefore(start);

  Shift copyWith({DateTime? checkedInAt}) => Shift(
        shiftId: shiftId,
        start: start,
        end: end,
        label: label,
        zoneName: zoneName,
        zoneDetail: zoneDetail,
        zoneIds: zoneIds,
        floorName: floorName,
        storeName: storeName,
        teammates: teammates,
        checkedInAt: checkedInAt ?? this.checkedInAt,
        checkInOpensAt: _checkInOpensAt,
      );
}

/// Whether this staff member can currently be offered Tasks (BR-19, BR-23, BR-35):
/// on shift, checked in, assigned to the zone, and below the active-task limit.
class Eligibility {
  const Eligibility({required this.checkedIn, required this.activeTasks, this.zoneName, this.limit = workloadLimit, this.shiftEndsAt});

  static const workloadLimit = 2;

  final bool checkedIn;
  final int activeTasks;
  final String? zoneName;

  /// End of the checked-in shift; "Handle later" cannot promise a start after it.
  final DateTime? shiftEndsAt;

  /// The server's limit (`maxActiveTasks`); BR-23 says 2.
  final int limit;

  bool get atWorkloadLimit => activeTasks >= limit;
  bool get canReceiveOffers => checkedIn && !atWorkloadLimit;
}

/// TaskOffer V7: `PENDING` is [open]; `CANCELLED` splits by `closedReason` into [takenByOther],
/// [eventCleared] (the OperationalEvent recovered before anyone accepted) and [withdrawn] (any
/// other reason). `expired`: this Staff member did not respond in time, which is not a decline.
enum OfferStatus { open, takenByOther, accepted, declined, expired, eventCleared, withdrawn }

/// A Task offered to eligible zone staff. The first valid acceptance wins (BR-21).
class TaskOffer {
  const TaskOffer({
    required this.offerId,
    required this.origin,
    required this.sourceCode,
    required this.title,
    required this.priority,
    required this.zoneName,
    required this.location,
    required this.measurement,
    required this.instructions,
    required this.createdAt,
    required this.recipients,
    required this.attempt,
    required this.nextAlertAt,
    this.maxAttempts = defaultMaxAttempts,
    this.status = OfferStatus.open,
    this.takenBy,
    this.takenAt,
    this.cameraCode,
    this.eventTypeCode,
    this.raisedFrom,
    this.eventClearedAt,
    this.expiresAt,
    this.dispatchScope,
  });

  /// BR-22: re-notify every 60 s up to the configured limit, then the Operator assigns manually.
  static const defaultMaxAttempts = 3;
  static const realertInterval = Duration(seconds: 60);

  final String offerId;
  final TaskOrigin origin;

  /// EVT-…, INC-… or RPT-… of the record that produced this Task.
  final String sourceCode;
  final String title;
  final Severity priority;
  final String zoneName;
  final String location;
  final String measurement;
  final String instructions;
  final DateTime createdAt;
  /// How many staff members the offer went to.
  final int recipients;
  final int attempt;

  /// Total offers before the Operator takes over (server `SystemSetting`, 3 by default).
  final int maxAttempts;
  /// When the offer goes out again. Null on the last offer: the server then hands the task to
  /// the Operator instead of re-offering it.
  final DateTime? nextAlertAt;
  final OfferStatus status;
  final String? takenBy;
  final DateTime? takenAt;
  final String? cameraCode;

  /// OperationalEventType code (`LONG_QUEUE`, `EXCESSIVE_WAIT`, `CONGESTION`, `CHECKOUT_CAPACITY`)
  /// for offers that come from an OperationalEvent.
  final String? eventTypeCode;

  /// Priority before the event escalated on the same episode (WARNING → CRITICAL); null if never raised.
  final Severity? raisedFrom;
  final DateTime? eventClearedAt;

  /// TaskOffer V7 `expires_at`: when this offer ends for this Staff member.
  final DateTime? expiresAt;

  /// TaskOffer V7 `dispatch_scope`: how far the search has reached.
  final String? dispatchScope;

  bool get isOpen => status == OfferStatus.open;

  /// V7 widens the search in waves with no fixed limit, so there is no "of N" once it applies.
  String get roundLabel => expiresAt != null ? 'offer round $attempt' : 'offer $attempt of $maxAttempts';

  TaskOffer copyWith({
    int? attempt,
    DateTime? nextAlertAt,
    OfferStatus? status,
    String? takenBy,
    DateTime? takenAt,
    Severity? priority,
    String? measurement,
    Severity? raisedFrom,
    DateTime? eventClearedAt,
    DateTime? expiresAt,
  }) =>
      TaskOffer(
        offerId: offerId,
        origin: origin,
        sourceCode: sourceCode,
        title: title,
        priority: priority ?? this.priority,
        zoneName: zoneName,
        location: location,
        measurement: measurement ?? this.measurement,
        instructions: instructions,
        createdAt: createdAt,
        recipients: recipients,
        attempt: attempt ?? this.attempt,
        maxAttempts: maxAttempts,
        nextAlertAt: nextAlertAt ?? this.nextAlertAt,
        status: status ?? this.status,
        takenBy: takenBy ?? this.takenBy,
        takenAt: takenAt ?? this.takenAt,
        cameraCode: cameraCode,
        eventTypeCode: eventTypeCode,
        raisedFrom: raisedFrom ?? this.raisedFrom,
        eventClearedAt: eventClearedAt ?? this.eventClearedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        dispatchScope: dispatchScope,
      );
}

/// Staff responses to a Task offer. Accepting responsibility (now or later) is distinct
/// from starting work; `Cannot Handle` is a response, not an evidence rejection.
enum TaskResponse { handleNow, handleLater, cannotHandle }

/// Configurable delays for "Accept and Handle Later".
const handleLaterOptions = [Duration(minutes: 5), Duration(minutes: 10), Duration(minutes: 15), Duration(minutes: 30)];

enum DeclineReason {
  busy('BUSY', 'Busy with another task'),
  unavailable('UNAVAILABLE', 'Unavailable'),
  notQualified('NOT_QUALIFIED', 'Not qualified'),
  other('OTHER', 'Other');

  const DeclineReason(this.code, this.label);

  /// TaskOffer V7 `decline_reason_code`.
  final String code;
  final String label;
}

/// Server Task states for the assignee. SUBMITTED waits for the Operator to verify the work;
/// only VERIFIED means it was confirmed done.
enum TaskStatus {
  accepted('Accepted'),
  inProgress('In progress'),
  submitted('Waiting for verification'),
  verified('Verified'),
  cancelled('Cancelled');

  const TaskStatus(this.label);
  final String label;
}

class StaffTask {
  const StaffTask({
    required this.taskId,
    required this.origin,
    required this.sourceCode,
    required this.title,
    required this.priority,
    required this.zoneName,
    required this.location,
    required this.instructions,
    required this.createdAt,
    required this.acceptedAt,
    required this.status,
    this.plannedStartAt,
    this.startedAt,
    this.cameraCode,
    this.eventTypeCode,
    this.raisedFrom,
    this.eventClearedAt,
  });

  final String taskId;
  final TaskOrigin origin;
  final String sourceCode;
  final String title;
  final Severity priority;
  final String zoneName;
  final String location;
  final String instructions;
  final DateTime createdAt;
  final DateTime acceptedAt;
  final TaskStatus status;

  /// Set when the staff member chose "Accept and Handle Later".
  final DateTime? plannedStartAt;
  final DateTime? startedAt;
  final String? cameraCode;
  final String? eventTypeCode;
  final Severity? raisedFrom;

  /// Set when the source OperationalEvent recovered while this task was still open. The task
  /// stays with the staff member, who checks the area and finishes it (provisional demo behaviour).
  final DateTime? eventClearedAt;

  bool get isActive => status == TaskStatus.accepted || status == TaskStatus.inProgress;
  bool get isDeferred => status == TaskStatus.accepted && plannedStartAt != null;

  /// Responsibility accepted but work not started by the promised time.
  bool isOverdueAt(DateTime now) => isDeferred && now.isAfter(plannedStartAt!);

  StaffTask copyWith({TaskStatus? status, DateTime? startedAt, Severity? priority, Severity? raisedFrom, DateTime? eventClearedAt}) =>
      StaffTask(
        taskId: taskId,
        origin: origin,
        sourceCode: sourceCode,
        title: title,
        priority: priority ?? this.priority,
        zoneName: zoneName,
        location: location,
        instructions: instructions,
        createdAt: createdAt,
        acceptedAt: acceptedAt,
        status: status ?? this.status,
        plannedStartAt: plannedStartAt,
        startedAt: startedAt ?? this.startedAt,
        cameraCode: cameraCode,
        eventTypeCode: eventTypeCode,
        raisedFrom: raisedFrom ?? this.raisedFrom,
        eventClearedAt: eventClearedAt ?? this.eventClearedAt,
      );
}

enum NotificationKind {
  taskOffered,
  taskAccepted,
  offerTaken,
  offerEscalated,
  eventEscalated,
  eventCleared,
  reportSent,
  shiftStarted,
  shiftChanged,
  swapUpdated,
  general,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.severity,
    this.taskId,
    this.read = false,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final Severity? severity;
  final String? taskId;
  final bool read;

  AppNotification markRead() => AppNotification(
        id: id,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        severity: severity,
        taskId: taskId,
        read: true,
      );
}

/// BR-16: a confirmed StaffReport is either a routine operational request (may create a
/// Task) or a potential Incident that goes through Incident qualification.
enum ReportKind {
  routineRequest('Routine request', 'Something that needs doing, no safety risk'),
  potentialIncident('Potential incident', 'Safety risk or something disrupting operations');

  const ReportKind(this.label, this.hint);
  final String label;
  final String hint;
}

class ReportCategory {
  const ReportCategory(this.name, this.kind);
  final String name;
  final ReportKind kind;
}

/// Incident categories (BR-07: safety, obstruction, equipment, cleanliness) and routine requests.
const reportCategories = [
  ReportCategory('Spill / broken item', ReportKind.potentialIncident),
  ReportCategory('Equipment fault', ReportKind.potentialIncident),
  ReportCategory('Pathway obstruction', ReportKind.potentialIncident),
  ReportCategory('Cleanliness problem', ReportKind.potentialIncident),
  ReportCategory('Safety hazard', ReportKind.potentialIncident),
  ReportCategory('Restock or shelf tidy', ReportKind.routineRequest),
  ReportCategory('Customer needs help', ReportKind.routineRequest),
  ReportCategory('Checkout needs support', ReportKind.routineRequest),
  ReportCategory('Other', ReportKind.routineRequest),
];

ReportKind kindOf(String category) =>
    reportCategories.firstWhere((c) => c.name == category, orElse: () => reportCategories.last).kind;

enum ReportSeverity {
  low('Low', Severity.info),
  medium('Medium', Severity.warning),
  high('High', Severity.critical);

  const ReportSeverity(this.label, this.severity);
  final String label;
  final Severity severity;
}

enum ReportField { kind, type, location, severity, title, suggestedAction }

class ReportOption {
  const ReportOption(this.code, this.name, {this.allowedTaskCodes = const [], this.routineEligible = false});
  final String code;
  final String name;
  final List<String> allowedTaskCodes;
  final bool routineEligible;
}

class ReportZoneOption {
  const ReportZoneOption(this.id, this.name, this.floorName);
  final String id;
  final String name;
  final String floorName;
}

/// The report as extracted by AI and then confirmed or corrected by the staff member (BR-17).
class ReportDraft {
  const ReportDraft({
    required this.note,
    required this.photoPaths,
    required this.kind,
    required this.type,
    required this.location,
    required this.severity,
    required this.title,
    required this.suggestedAction,
    required this.aiFields,
    this.fromVoice = false,
    this.edited = false,
    this.live = false,
    this.typeCode,
    this.zoneId,
    this.taskTypeCodes = const [],
    this.incidentTypes = const [],
    this.taskTypes = const [],
    this.zones = const [],
    this.duplicateDecision,
    this.routineTaskDecision,
    this.reportId,
    this.confirmedScenarioCode,
    this.description = '',
    this.confidenceLevel,
    this.evidence,
    this.voicePath,
    this.aiIssue,
  });

  final String note;
  final List<String> photoPaths;
  final ReportKind kind;
  final String type;
  final String location;
  final ReportSeverity severity;
  final String title;
  final String suggestedAction;
  final bool fromVoice;
  final bool live;
  final String? typeCode;
  final String? zoneId;
  final List<String> taskTypeCodes;
  final List<ReportOption> incidentTypes;
  final List<ReportOption> taskTypes;
  final List<ReportZoneOption> zones;
  final String? duplicateDecision;
  final String? routineTaskDecision;
  final String? reportId;
  final String? confirmedScenarioCode;
  final String description;
  /// Model self-assessment, not a calibrated probability or approval.
  final String? confidenceLevel;
  final String? evidence;
  final String? voicePath;

  /// Why the AI suggestion is missing (server error code and message); null when the AI answered.
  final String? aiIssue;

  /// True once the staff member changed any field the AI filled in.
  final bool edited;

  /// Fields still holding the AI's value; editing a field removes it from this set.
  final Set<ReportField> aiFields;

  ReportDraft edit(ReportField field, {String? text, ReportSeverity? severity, ReportKind? kind}) {
    // Picking a category also picks its kind unless the staff member already chose one.
    final nextKind = field == ReportField.kind
        ? kind!
        : field == ReportField.type && !live && aiFields.contains(ReportField.kind)
            ? kindOf(text!)
            : this.kind;
    return ReportDraft(
      note: note,
      photoPaths: photoPaths,
      kind: nextKind,
      type: field == ReportField.type ? text! : field == ReportField.kind && live ? '' : type,
      location: field == ReportField.location ? text! : location,
      severity: field == ReportField.severity ? severity! : this.severity,
      title: field == ReportField.title ? text! : title,
      suggestedAction: field == ReportField.suggestedAction ? text! : suggestedAction,
      aiFields: {...aiFields}..remove(field),
      fromVoice: fromVoice,
      edited: true,
      live: live,
      typeCode: field == ReportField.type && live ?
          (nextKind == ReportKind.potentialIncident ? incidentTypes : taskTypes).where((x) => x.name == text).firstOrNull?.code : field == ReportField.kind && live ? null : typeCode,
      zoneId: zoneId,
      taskTypeCodes: (field == ReportField.type || field == ReportField.kind) && live ? [] : taskTypeCodes,
      incidentTypes: incidentTypes,
      taskTypes: taskTypes,
      zones: zones,
      duplicateDecision: field == ReportField.type || field == ReportField.kind ? null : duplicateDecision,
      routineTaskDecision: field == ReportField.type || field == ReportField.kind ? null : routineTaskDecision,
      reportId: reportId,
      confirmedScenarioCode: field == ReportField.type || field == ReportField.kind ? null : confirmedScenarioCode,
      description: description,
      confidenceLevel: confidenceLevel,
      evidence: evidence,
      voicePath: voicePath,
      aiIssue: aiIssue,
    );
  }

  ReportDraft withSelection({String? zoneId, List<String>? taskTypeCodes, String? duplicateDecision, String? routineTaskDecision,
      String? confirmedScenarioCode, bool clearScenario = false, String? description, bool markEdited = true}) => ReportDraft(
    note: note, photoPaths: photoPaths, kind: kind, type: type, location: location, severity: severity,
    title: title, suggestedAction: suggestedAction, aiFields: aiFields, fromVoice: fromVoice, edited: edited || markEdited,
    live: live, typeCode: typeCode, zoneId: zoneId ?? this.zoneId,
    taskTypeCodes: taskTypeCodes ?? this.taskTypeCodes, incidentTypes: incidentTypes, taskTypes: taskTypes,
    zones: zones, duplicateDecision: zoneId != null && zoneId != this.zoneId ? null : duplicateDecision ?? this.duplicateDecision,
    routineTaskDecision: zoneId != null && zoneId != this.zoneId ? null : routineTaskDecision ?? this.routineTaskDecision, reportId: reportId,
    confirmedScenarioCode: clearScenario ? null : confirmedScenarioCode ?? this.confirmedScenarioCode,
    description: description ?? this.description,
    confidenceLevel: confidenceLevel,
    evidence: evidence,
    voicePath: voicePath,
    aiIssue: aiIssue,
  );

  ReportDraft defaultZoneFromShift(Shift? shift) {
    if (!live || shift == null || !shift.isCheckedIn || shift.zoneIds.length != 1 || zoneId != null) return this;
    final id = shift.zoneIds.single;
    return zones.any((z) => z.id == id) ? withSelection(zoneId: id, markEdited: false) : this;
  }

  String? validate() {
    if (title.trim().isEmpty) return 'Add a short title so staff know what to look for.';
    if (location.trim().isEmpty && !live) return 'Add where the issue is.';
    if (live && zoneId == null) return 'Select a Zone.';
    if (live && typeCode == null) return 'Select a category.';
    if (live && kind == ReportKind.potentialIncident && taskTypeCodes.isEmpty) return 'Select at least one corrective Task type.';
    if (live && confirmedScenarioCode == 'EXPOSED_ELECTRICAL_WIRE' &&
        !(taskTypeCodes.length == 2 && taskTypeCodes.contains('TT-12') && taskTypeCodes.contains('TT-13'))) {
      return 'Exposed electrical wire requires TT-12 and TT-13.';
    }
    return null;
  }
}

/// What the confirmed report became.
enum ReportOutcome {
  /// Routine request recorded; a Task was offered to zone staff.
  routineTask,

  /// Potential incident qualified as an Incident; a corrective Task was offered.
  incidentQualified,

  /// Potential incident recorded for qualification; no Incident opened yet.
  awaitingQualification,
}

class ReportReceipt {
  const ReportReceipt({
    required this.reportCode,
    required this.outcome,
    required this.title,
    required this.location,
    required this.zoneName,
    required this.offeredTo,
    required this.submittedAt,
    required this.edited,
    this.incidentCode,
    this.preview = false,
  });

  final String reportCode;
  final ReportOutcome outcome;
  final String? incidentCode;
  final String title;
  final String location;
  final String zoneName;
  final int offeredTo;
  final DateTime submittedAt;
  final bool edited;

  /// Made in the app only: the server has no StaffReport API yet, so nothing was sent.
  final bool preview;
}

enum SwapReason {
  personal('PERSONAL', 'Personal matter'),
  health('HEALTH', 'Health'),
  study('STUDY', 'Study or exam'),
  other('OTHER', 'Other');

  const SwapReason(this.code, this.label);

  /// `ShiftSwapRequest.reason_code` on the backend.
  final String code;
  final String label;

  static SwapReason? fromCode(String? code) => values.where((r) => r.code == code).firstOrNull;
}

/// SWAP exchanges my shift for one of the colleague's; COVER hands my shift to the colleague.
enum SwapType {
  swap('SWAP', 'Swap shifts'),
  cover('COVER', 'Ask to cover');

  const SwapType(this.code, this.label);
  final String code;
  final String label;

  static SwapType fromCode(String? code) => code == 'COVER' ? cover : swap;
}

/// A → PENDING_PEER → B accepts → PENDING_MANAGER → APPROVED / REJECTED. A pending request can also
/// end as DECLINED_BY_PEER, CANCELLED or EXPIRED (24 h before the earliest affected shift).
enum SwapStatus {
  pendingPeer('PENDING_PEER', 'Waiting for colleague'),
  pendingManager('PENDING_MANAGER', 'Waiting for the Manager'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected by the Manager'),
  declinedByPeer('DECLINED_BY_PEER', 'Declined by colleague'),
  cancelled('CANCELLED', 'Cancelled'),
  expired('EXPIRED', 'Expired');

  const SwapStatus(this.code, this.label);
  final String code;
  final String label;

  bool get isOpen => this == pendingPeer || this == pendingManager;

  static SwapStatus fromCode(String code) => values.firstWhere((s) => s.code == code, orElse: () => cancelled);
}

/// One shift assignment as a swap request sees it.
class SwapShift {
  const SwapShift({
    required this.shiftId,
    required this.ownerId,
    required this.label,
    required this.start,
    required this.end,
    required this.zoneName,
  });

  final String shiftId;
  final String ownerId;
  final String label;
  final DateTime start;
  final DateTime end;
  final String zoneName;
}

/// Staff A asks colleague B; B accepts or declines; then a Manager approves (MF-04).
class ShiftSwapRequest {
  const ShiftSwapRequest({
    required this.requestId,
    required this.type,
    required this.status,
    required this.requesterId,
    required this.requesterName,
    required this.requesterShift,
    required this.submittedAt,
    required this.sentByMe,
    this.targetId,
    this.targetName,
    this.targetShift,
    this.reason,
    this.note = '',
    this.expiresAt,
    this.targetRespondedAt,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.cancelledBy,
    this.cancelledAt,
    this.cancellationReason,
    this.canCancel = false,
    this.canRespond = false,
  });

  final String requestId;
  final SwapType type;
  final SwapStatus status;
  final String requesterId;
  final String requesterName;
  final SwapShift requesterShift;
  final String? targetId;
  final String? targetName;

  /// The colleague's shift that comes back in a SWAP; null for COVER.
  final SwapShift? targetShift;
  final SwapReason? reason;
  final String note;
  final DateTime submittedAt;

  /// After this moment the request expires and the schedule stays as it is.
  final DateTime? expiresAt;
  final DateTime? targetRespondedAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? decisionNote;
  final String? cancelledBy;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  /// True when I am the requester (A), false when I am the colleague asked (B).
  final bool sentByMe;
  final bool canCancel;
  final bool canRespond;

  /// The requester's shift, i.e. the shift this request is about.
  String get shiftId => requesterShift.shiftId;

  /// The other person from my point of view.
  String get otherName => (sentByMe ? targetName : requesterName) ?? 'Colleague';

  /// PENDING_MANAGER without a target is a Staff escalation asking the Manager to choose cover.
  bool get managerNeedsToAssign => status == SwapStatus.pendingManager && targetId == null;

  /// What I hand over and what I get back if the request is approved.
  SwapShift? get iGive => sentByMe ? requesterShift : targetShift;
  SwapShift? get iGet => sentByMe ? targetShift : requesterShift;
}

/// A colleague who passes every swap rule, with the shift they would give back for a SWAP.
class SwapCandidate {
  const SwapCandidate({required this.userId, required this.fullName, required this.weeklyHoursAfter, this.shift, this.recommended = true});

  final String userId;
  final String fullName;
  final SwapShift? shift;

  /// The colleague's hours that week if the request is approved.
  final double weeklyHoursAfter;
  final bool recommended;
}

class SwapCandidates {
  const SwapCandidates({required this.shiftId, required this.type, required this.deadline, required this.candidates, required this.hiddenCount});

  final String shiftId;
  final SwapType type;

  /// The request must be decided by then (24 h before the shift).
  final DateTime deadline;
  final List<SwapCandidate> candidates;

  /// Colleagues left out because a rule fails for them.
  final int hiddenCount;
}

/// Photo slots of a completion record (BR-26).
enum EvidenceKind {
  before('BEFORE_PHOTO', 'Before'),
  after('AFTER_PHOTO', 'After');

  const EvidenceKind(this.code, this.label);
  final String code;
  final String label;

  static EvidenceKind fromCode(String code) => values.firstWhere((k) => k.code == code);
}

/// A photo the server holds. [imageUrl] needs the signed-in session to load.
class EvidencePhoto {
  const EvidencePhoto({required this.evidenceId, required this.kind, required this.imageUrl, required this.capturedAt});
  final String evidenceId;
  final EvidenceKind kind;
  final String imageUrl;
  final DateTime capturedAt;
}

enum ReviewStatus { pending, verified, rejected }

/// One submitted completion record and the Operator's decision on it.
class TaskSubmission {
  const TaskSubmission({
    required this.submissionId,
    required this.note,
    required this.submittedAt,
    required this.status,
    this.rejectReason,
    this.photos = const [],
  });
  final String submissionId;
  final String note;
  final DateTime submittedAt;
  final ReviewStatus status;
  final String? rejectReason;
  final List<EvidencePhoto> photos;
}

/// What a task needs before submission, the photos uploaded so far and earlier submissions (newest first).
class TaskEvidenceState {
  const TaskEvidenceState({
    required this.taskId,
    required this.requiresBefore,
    required this.requiresAfter,
    this.rejectionCount = 0,
    this.drafts = const [],
    this.submissions = const [],
  });
  final String taskId;
  final bool requiresBefore;
  final bool requiresAfter;
  final int rejectionCount;
  final List<EvidencePhoto> drafts;
  final List<TaskSubmission> submissions;

  bool requires(EvidenceKind kind) => kind == EvidenceKind.before ? requiresBefore : requiresAfter;
  EvidencePhoto? draft(EvidenceKind kind) => drafts.where((d) => d.kind == kind).firstOrNull;
  TaskSubmission? get latest => submissions.firstOrNull;

  /// The last submission came back from the Operator for rework.
  bool get inRework => latest?.status == ReviewStatus.rejected;
}

class CheckInTooEarly implements Exception {
  const CheckInTooEarly(this.opensAt);
  final DateTime opensAt;
}

/// Who took the task is known when the server says so; a withdrawn offer may not name them.
class TaskAlreadyTaken implements Exception {
  const TaskAlreadyTaken({this.takenBy, this.takenAt});
  final String? takenBy;
  final DateTime? takenAt;
}

class WorkloadLimitReached implements Exception {
  const WorkloadLimitReached();
}

class OfferNoLongerOpen implements Exception {
  const OfferNoLongerOpen();
}

class SwapNotAllowed implements Exception {
  const SwapNotAllowed(this.message);
  final String message;
}

/// Any other refused or failed call, with a message that can be shown as is.
class OperationFailed implements Exception {
  const OperationFailed(this.message);
  final String message;

  @override
  String toString() => message;
}
