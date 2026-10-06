import Foundation
import SwiftData

// CloudKit 제약: 모든 속성에 기본값 · 관계는 모두 옵셔널 · @Attribute(.unique) 금지.
// 출시 후에는 필드를 추가만 할 수 있으니 처음부터 넉넉하게 잡아둬요.

enum PlanSource: String, Codable, CaseIterable {
    case manual, timetable, calendar, todo
}

enum Confirmation: String, Codable, CaseIterable {
    case done, partial, other, skip

    var label: String {
        switch self {
        case .done: return "계획대로 했어요"
        case .partial: return "일부만 했어요"
        case .other: return "다른 걸 했어요"
        case .skip: return "건너뛰었어요"
        }
    }

    var symbol: String {
        switch self {
        case .done: return "checkmark"
        case .partial: return "circle.lefthalf.filled"
        case .other: return "arrow.left.arrow.right"
        case .skip: return "xmark"
        }
    }
}

enum ActualSource: String, Codable {
    case timer, confirm, gapFill, health, manual
}

enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week: return "주간"
        case .month: return "월간"
        case .year: return "연간"
        }
    }
}

enum CalendarLinkMode: String, Codable {
    case importAs = "import"
    case ignore
}

@Model
final class ActivityCategory {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#3B66BE"
    var themeID: String? = nil
    var sortOrder: Int = 0
    var archivedAt: Date? = nil
    var seedKey: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ActivityDetail.category)
    var details: [ActivityDetail]? = []

    @Relationship(deleteRule: .cascade, inverse: \Goal.category)
    var goals: [Goal]? = []

    init(name: String, colorHex: String, themeID: String? = "basic", sortOrder: Int = 0, seedKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.themeID = themeID
        self.sortOrder = sortOrder
        self.seedKey = seedKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isArchived: Bool { archivedAt != nil }

    var sortedDetails: [ActivityDetail] {
        (details ?? []).sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    var activeDetails: [ActivityDetail] {
        sortedDetails.filter { $0.archivedAt == nil }
    }
}

@Model
final class ActivityDetail {
    var id: UUID = UUID()
    var name: String = ""
    var category: ActivityCategory? = nil
    var sortOrder: Int = 0
    var archivedAt: Date? = nil
    var seedKey: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \PlanBlock.detail)
    var plans: [PlanBlock]? = []

    @Relationship(deleteRule: .nullify, inverse: \ActualRecord.detail)
    var actuals: [ActualRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \TimetableSlot.detail)
    var slots: [TimetableSlot]? = []

    @Relationship(deleteRule: .nullify, inverse: \CalendarLink.detail)
    var calendarLinks: [CalendarLink]? = []

    @Relationship(deleteRule: .nullify, inverse: \ReminderLink.detail)
    var reminderLinks: [ReminderLink]? = []

    @Relationship(deleteRule: .cascade, inverse: \Goal.detail)
    var goals: [Goal]? = []

    // 관계는 insert 뒤에 연결해요 (DataStore의 make… 함수).
    init(name: String, sortOrder: Int = 0, seedKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.seedKey = seedKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isArchived: Bool { archivedAt != nil || category?.archivedAt != nil }
    var fullName: String { "\(category?.name ?? "미분류") · \(name)" }
    var pathName: String { "\(category?.name ?? "미분류") › \(name)" }
    var colorHex: String { category?.colorHex ?? "#52606F" }
}

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var detail: ActivityDetail? = nil
    var start: Date = Date()
    var end: Date = Date()
    var sourceRaw: String = PlanSource.manual.rawValue
    /// 캘린더 일정·미리알림의 calendarItemExternalIdentifier
    var ekExternalID: String? = nil
    /// 시간표 칸을 저장했을 때 "dayKey|slotID" — 기기마다 따로 만들어도 하나만 남겨요.
    var slotKey: String? = nil
    var dayKey: String = ""
    var title: String? = nil
    var askWhenDone: Bool = true
    var confirmationRaw: String? = nil
    var note: String? = nil
    /// 시간표 · 캘린더 칸을 그날만 지웠을 때
    var isCancelled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \ActualRecord.planBlock)
    var actuals: [ActualRecord]? = []

    init(start: Date, end: Date, source: PlanSource, dayKey: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.sourceRaw = source.rawValue
        self.dayKey = dayKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var source: PlanSource {
        get { PlanSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var confirmation: Confirmation? {
        get { confirmationRaw.flatMap(Confirmation.init(rawValue:)) }
        set { confirmationRaw = newValue?.rawValue; updatedAt = Date() }
    }

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

@Model
final class ActualRecord {
    var id: UUID = UUID()
    var detail: ActivityDetail? = nil
    var start: Date = Date()
    /// nil = 기록 중
    var end: Date? = nil
    var sourceRaw: String = ActualSource.timer.rawValue
    var planBlock: PlanBlock? = nil
    /// 타이머를 시작한 기기
    var deviceName: String? = nil
    var note: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(start: Date, end: Date?, source: ActualSource) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var source: ActualSource {
        get { ActualSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isRunning: Bool { end == nil }
}

@Model
final class Timetable {
    var id: UUID = UUID()
    var name: String = ""
    var startDate: Date? = nil
    var endDate: Date? = nil
    var isActive: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TimetableSlot.timetable)
    var slots: [TimetableSlot]? = []

    init(name: String, isActive: Bool = false, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedSlots: [TimetableSlot] {
        (slots ?? []).sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
    }
}

@Model
final class TimetableSlot {
    var id: UUID = UUID()
    var timetable: Timetable? = nil
    var detail: ActivityDetail? = nil
    /// Calendar 기준 1(일)–7(토)
    var weekday: Int = 2
    var startMinute: Int = 540
    var endMinute: Int = 600
    var place: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(weekday: Int, startMinute: Int, endMinute: Int, place: String? = nil) {
        self.id = UUID()
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.place = place
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var durationMinutes: Int { max(0, endMinute - startMinute) }
}

/// 한 줄만 존재해요.
@Model
final class AppPreferences {
    var id: UUID = UUID()
    var dayStartMinute: Int = 360
    var dayEndMinute: Int = 1560
    /// 하루 마감 알림: 끝나기 몇 분 전 (0 이하 = 끄기)
    var closeReminderOffset: Int = 60
    var customColors: [String] = []
    var activeThemeID: String = "basic"
    var askWhenDone: Bool = true
    var showCalendarEvents: Bool = false
    var reminderListKeys: [String] = []
    var includeArchivedInStats: Bool = true
    var healthEnabled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class CalendarLink {
    var id: UUID = UUID()
    /// 계정 종류 + 캘린더 이름 (기기마다 캘린더 ID가 달라서)
    var calendarKey: String = ""
    var calendarTitle: String = ""
    var detail: ActivityDetail? = nil
    var modeRaw: String = CalendarLinkMode.importAs.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(calendarKey: String, calendarTitle: String, mode: CalendarLinkMode) {
        self.id = UUID()
        self.calendarKey = calendarKey
        self.calendarTitle = calendarTitle
        self.modeRaw = mode.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var mode: CalendarLinkMode {
        get { CalendarLinkMode(rawValue: modeRaw) ?? .importAs }
        set { modeRaw = newValue.rawValue }
    }
}

@Model
final class ReminderLink {
    var id: UUID = UUID()
    var externalID: String = ""
    var detail: ActivityDetail? = nil
    var createdAt: Date = Date()

    init(externalID: String) {
        self.id = UUID()
        self.externalID = externalID
        self.createdAt = Date()
    }
}

@Model
final class Goal {
    var id: UUID = UUID()
    /// category와 detail 중 하나만
    var category: ActivityCategory? = nil
    var detail: ActivityDetail? = nil
    var periodRaw: String = GoalPeriod.week.rawValue
    var targetMinutes: Int = 600
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(period: GoalPeriod, targetMinutes: Int) {
        self.id = UUID()
        self.periodRaw = period.rawValue
        self.targetMinutes = targetMinutes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var period: GoalPeriod {
        get { GoalPeriod(rawValue: periodRaw) ?? .week }
        set { periodRaw = newValue.rawValue }
    }

    var displayName: String { detail?.name ?? category?.name ?? "목표" }
    var colorHex: String { detail?.colorHex ?? category?.colorHex ?? "#52606F" }
}

@Model
final class DaySummary {
    var id: UUID = UUID()
    var dayKey: String = ""
    var note: String = ""
    var closedAt: Date? = nil
    var matchRate: Double? = nil
    /// 그날의 하루 범위 스냅샷
    var rangeStartMinute: Int = 360
    var rangeEndMinute: Int = 1560
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(dayKey: String, rangeStartMinute: Int, rangeEndMinute: Int) {
        self.id = UUID()
        self.dayKey = dayKey
        self.rangeStartMinute = rangeStartMinute
        self.rangeEndMinute = rangeEndMinute
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        ActivityCategory.self, ActivityDetail.self, PlanBlock.self, ActualRecord.self,
        Timetable.self, TimetableSlot.self, AppPreferences.self, CalendarLink.self,
        ReminderLink.self, Goal.self, DaySummary.self
    ]
    static var schema: Schema { Schema(models) }
}
