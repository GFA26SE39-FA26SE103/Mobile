// Domain model for the Staff side of Mainflow 2, following the 10/10/2026 baseline:
// Measurement → OperationalEvent → ResponsePolicy → Task offer / qualified Incident,
// plus the separate confirmed StaffReport path.

/// Priority of an OperationalEvent or severity of a qualified Incident.
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
    required this.zoneDetail,
    required this.floorName,
    required this.storeName,
    required this.teammates,
    this.checkedInAt,
  });

  final String shiftId;
  final DateTime start;
  final DateTime end;
  final String label;
  final String zoneName;
  final String zoneDetail;
  final String floorName;
  final String storeName;
  final List<String> teammates;
  final DateTime? checkedInAt;

  /// BR: check-in opens 15 minutes before the shift starts.
  static const checkInWindow = Duration(minutes: 15);
  DateTime get checkInOpensAt => start.subtract(checkInWindow);

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
        floorName: floorName,
        storeName: storeName,
        teammates: teammates,
        checkedInAt: checkedInAt ?? this.checkedInAt,
      );
}

/// Whether this staff member can currently be offered Tasks (BR-19, BR-23, BR-35):
/// on shift, checked in, assigned to the zone, and below the active-task limit.
class Eligibility {
  const Eligibility({required this.checkedIn, required this.activeTasks, this.zoneName});

  static const workloadLimit = 2;

  final bool checkedIn;
  final int activeTasks;
  final String? zoneName;

  bool get atWorkloadLimit => activeTasks >= workloadLimit;
  bool get canReceiveOffers => checkedIn && !atWorkloadLimit;
}

/// `eventCleared`: the OperationalEvent episode recovered before anyone accepted (provisional
/// demo behaviour; see open point 5 in docs/API_CONTRACT.md).
enum OfferStatus { open, takenByOther, accepted, declined, escalated, eventCleared }

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
    this.status = OfferStatus.open,
    this.takenBy,
    this.takenAt,
    this.cameraCode,
    this.eventTypeCode,
    this.raisedFrom,
    this.eventClearedAt,
  });

  /// BR-22: re-notify every 60 s up to the configured limit, then the Operator assigns manually.
  static const maxAttempts = 3;
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
  final List<String> recipients;
  final int attempt;
  final DateTime nextAlertAt;
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

  bool get isOpen => status == OfferStatus.open;

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
        nextAlertAt: nextAlertAt ?? this.nextAlertAt,
        status: status ?? this.status,
        takenBy: takenBy ?? this.takenBy,
        takenAt: takenAt ?? this.takenAt,
        cameraCode: cameraCode,
        eventTypeCode: eventTypeCode,
        raisedFrom: raisedFrom ?? this.raisedFrom,
        eventClearedAt: eventClearedAt ?? this.eventClearedAt,
      );
}

/// Staff responses to a Task offer. Accepting responsibility (now or later) is distinct
/// from starting work; `Cannot Handle` is a response, not an evidence rejection.
enum TaskResponse { handleNow, handleLater, cannotHandle }

/// Configurable delays for "Accept and Handle Later".
const handleLaterOptions = [Duration(minutes: 5), Duration(minutes: 10), Duration(minutes: 15), Duration(minutes: 30)];

enum DeclineReason {
  busy('Busy with another task'),
  onBreak('On break'),
  notNearZone('Not near the zone'),
  notQualified('Not trained for this task');

  const DeclineReason(this.label);
  final String label;
}

enum TaskStatus {
  accepted('Accepted'),
  inProgress('In progress'),
  done('Done');

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

  bool get isActive => status != TaskStatus.done;
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
  swapUpdated,
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

  /// True once the staff member changed any field the AI filled in.
  final bool edited;

  /// Fields still holding the AI's value; editing a field removes it from this set.
  final Set<ReportField> aiFields;

  ReportDraft edit(ReportField field, {String? text, ReportSeverity? severity, ReportKind? kind}) {
    // Picking a category also picks its kind unless the staff member already chose one.
    final nextKind = field == ReportField.kind
        ? kind!
        : field == ReportField.type && aiFields.contains(ReportField.kind)
            ? kindOf(text!)
            : this.kind;
    return ReportDraft(
      note: note,
      photoPaths: photoPaths,
      kind: nextKind,
      type: field == ReportField.type ? text! : type,
      location: field == ReportField.location ? text! : location,
      severity: field == ReportField.severity ? severity! : this.severity,
      title: field == ReportField.title ? text! : title,
      suggestedAction: field == ReportField.suggestedAction ? text! : suggestedAction,
      aiFields: {...aiFields}..remove(field),
      fromVoice: fromVoice,
      edited: true,
    );
  }

  String? validate() {
    if (title.trim().isEmpty) return 'Add a short title so staff know what to look for.';
    if (location.trim().isEmpty) return 'Add where the issue is.';
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
}

enum SwapReason {
  personal('Personal matter'),
  health('Health'),
  study('Study or exam'),
  other('Other');

  const SwapReason(this.label);
  final String label;
}

enum SwapStatus {
  pending('Waiting for Operator'),
  approved('Approved'),
  rejected('Rejected');

  const SwapStatus(this.label);
  final String label;
}

/// Staff-requested, Operator-approved shift swap (05/10/2026 workflow delta). The system
/// proposes replacement candidates; the Operator picks one. No direct Staff-to-Staff negotiation.
class ShiftSwapRequest {
  const ShiftSwapRequest({
    required this.requestId,
    required this.shiftId,
    required this.reason,
    required this.note,
    required this.submittedAt,
    required this.status,
    this.replacement,
    this.decisionNote,
  });

  final String requestId;
  final String shiftId;
  final SwapReason reason;
  final String note;
  final DateTime submittedAt;
  final SwapStatus status;
  final String? replacement;
  final String? decisionNote;
}

class CheckInTooEarly implements Exception {
  const CheckInTooEarly(this.opensAt);
  final DateTime opensAt;
}

class TaskAlreadyTaken implements Exception {
  const TaskAlreadyTaken({required this.takenBy, required this.takenAt});
  final String takenBy;
  final DateTime takenAt;
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
