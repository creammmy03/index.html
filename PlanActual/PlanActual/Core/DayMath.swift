import Foundation

/// 사용자가 정한 하루 범위. 끝은 다음 날로 넘어갈 수 있어요(최대 24시간).
struct DayClock: Equatable {
    var startMinute: Int
    var endMinute: Int

    init(startMinute: Int, endMinute: Int) {
        let s = ((startMinute % 1440) + 1440) % 1440
        var e = endMinute
        while e <= s { e += 1440 }
        while e - s > 1440 { e -= 1440 }
        self.startMinute = s
        self.endMinute = e
    }

    init(_ prefs: AppPreferences?) {
        self.init(startMinute: prefs?.dayStartMinute ?? 360, endMinute: prefs?.dayEndMinute ?? 1560)
    }

    static let standard = DayClock(startMinute: 360, endMinute: 1560)

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ko_KR")
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }

    var lengthMinutes: Int { endMinute - startMinute }
    var endsNextDay: Bool { endMinute > 1440 }

    /// 이 시각이 속한 '하루'의 자정
    func logicalDay(for date: Date) -> Date {
        let cal = Self.calendar
        let midnight = cal.startOfDay(for: date)
        let minutes = cal.dateComponents([.hour, .minute], from: date)
        let m = (minutes.hour ?? 0) * 60 + (minutes.minute ?? 0)
        if endsNextDay && m < endMinute - 1440 && m < startMinute {
            return cal.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        }
        return midnight
    }

    func range(for day: Date) -> DateInterval {
        let cal = Self.calendar
        let midnight = cal.startOfDay(for: day)
        let start = cal.date(byAdding: .minute, value: startMinute, to: midnight) ?? midnight
        let end = cal.date(byAdding: .minute, value: endMinute, to: midnight) ?? midnight.addingTimeInterval(86400)
        return DateInterval(start: start, end: max(start, end))
    }

    /// 하루 자정 + 분 (분은 하루 시작보다 이르면 다음 날로 넘겨요)
    func date(on day: Date, minute: Int) -> Date {
        let cal = Self.calendar
        let midnight = cal.startOfDay(for: day)
        var m = minute
        if m < startMinute && endsNextDay && m < endMinute - 1440 { m += 1440 }
        return cal.date(byAdding: .minute, value: m, to: midnight) ?? midnight
    }

    static func dayKey(_ day: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func day(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func addDays(_ n: Int, to day: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: day) ?? day
    }

    /// 그 주의 월요일 자정
    static func weekStart(for day: Date) -> Date {
        let cal = calendar
        let d = cal.startOfDay(for: day)
        let weekday = cal.component(.weekday, from: d) // 1 = 일
        let offset = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -offset, to: d) ?? d
    }

    static func weekDays(containing day: Date) -> [Date] {
        let start = weekStart(for: day)
        return (0..<7).map { addDays($0, to: start) }
    }

    static func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func weekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}

/// 날짜 · 시간 표시
enum Fmt {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.calendar = DayClock.calendar
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let hmF = formatter("HH:mm")
    private static let dayTitleF = formatter("M월 d일 EEEE")
    private static let monthDayF = formatter("M월 d일")
    private static let monthDayWeekF = formatter("M월 d일 (E)")
    private static let weekdayF = formatter("E")
    private static let weekdayLongF = formatter("EEEE")
    private static let dayNumF = formatter("d")

    static func hm(_ d: Date) -> String { hmF.string(from: d) }
    static func range(_ s: Date, _ e: Date) -> String { "\(hm(s))–\(hm(e))" }
    static func dayTitle(_ d: Date) -> String { dayTitleF.string(from: d) }
    static func monthDay(_ d: Date) -> String { monthDayF.string(from: d) }
    static func monthDayWeek(_ d: Date) -> String { monthDayWeekF.string(from: d) }
    static func weekdayShort(_ d: Date) -> String { weekdayF.string(from: d) }
    static func weekdayLong(_ d: Date) -> String { weekdayLongF.string(from: d) }
    static func dayNumber(_ d: Date) -> String { dayNumF.string(from: d) }

    /// 1시간 20분
    static func duration(_ minutes: Int) -> String {
        let m = abs(minutes)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)분" }
        if r == 0 { return "\(h)시간" }
        return "\(h)시간 \(r)분"
    }

    /// 3:20
    static func clock(_ minutes: Int) -> String {
        let m = abs(minutes)
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// +1:10 / −0:40
    static func signedClock(_ minutes: Int) -> String {
        if minutes == 0 { return "0:00" }
        return (minutes > 0 ? "+" : "−") + clock(minutes)
    }

    static func minuteLabel(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func percent(_ rate: Double?) -> String {
        guard let rate else { return "–" }
        return "\(Int((rate * 100).rounded()))%"
    }

    static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    /// Calendar weekday(1–7) 목록을 "월·수·금"으로
    static func weekdays(_ days: [Int]) -> String {
        let order = [2, 3, 4, 5, 6, 7, 1]
        let set = Set(days)
        if set == Set([2, 3, 4, 5, 6]) { return "평일" }
        if set == Set([1, 7]) { return "주말" }
        if set.count == 7 { return "매일" }
        return order.filter { set.contains($0) }.map { weekdaySymbols[$0 - 1] }.joined(separator: "·")
    }
}

extension DateInterval {
    func overlaps(start: Date, end: Date) -> Bool {
        start < self.end && end > self.start
    }

    var minutes: Int { Int((duration / 60).rounded()) }
}

extension Date {
    /// 15분 단위로 맞추기
    func snapped(toMinutes step: Int = 15) -> Date {
        let t = timeIntervalSinceReferenceDate
        let s = Double(step * 60)
        return Date(timeIntervalSinceReferenceDate: (t / s).rounded() * s)
    }

    func roundedUp(toMinutes step: Int) -> Date {
        let t = timeIntervalSinceReferenceDate
        let s = Double(step * 60)
        return Date(timeIntervalSinceReferenceDate: (t / s).rounded(.up) * s)
    }
}
