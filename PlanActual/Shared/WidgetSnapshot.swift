import Foundation

/// 앱이 계산해 App Group에 써두고 위젯이 읽는 오늘 요약.
struct WidgetSnapshot: Codable, Hashable {
    struct Band: Codable, Hashable {
        var start: Double   // 하루 범위 안 비율 0–1
        var end: Double
        var colorHex: String
    }

    var dayTitle: String
    var matchRate: Double?
    var planBands: [Band]
    var actualBands: [Band]
    var nowFraction: Double
    var nextTitle: String?
    var nextStart: Date?
    var updatedAt: Date

    static let placeholder = WidgetSnapshot(
        dayTitle: "오늘",
        matchRate: 0.72,
        planBands: [
            Band(start: 0.05, end: 0.25, colorHex: "#A83E74"),
            Band(start: 0.25, end: 0.5, colorHex: "#3B66BE"),
            Band(start: 0.55, end: 0.7, colorHex: "#23786F")
        ],
        actualBands: [
            Band(start: 0.08, end: 0.22, colorHex: "#A83E74"),
            Band(start: 0.22, end: 0.48, colorHex: "#3B66BE")
        ],
        nowFraction: 0.5,
        nextTitle: "휴식 · 저녁",
        nextStart: Date().addingTimeInterval(3600),
        updatedAt: Date()
    )

    static let empty = WidgetSnapshot(dayTitle: "오늘", matchRate: nil, planBands: [], actualBands: [],
                                      nowFraction: 0, nextTitle: nil, nextStart: nil, updatedAt: Date())

    static func load() -> WidgetSnapshot? {
        guard let data = SharedConfig.defaults.data(forKey: SharedConfig.widgetSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SharedConfig.defaults.set(data, forKey: SharedConfig.widgetSnapshotKey)
    }
}
