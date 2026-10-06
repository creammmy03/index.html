import Foundation
import SwiftData

/// 백업 · CSV 내보내기
@MainActor
enum CSVExporter {
    static func export(ctx: ModelContext) throws -> URL {
        var lines = ["종류,날짜,시작,끝,분,카테고리,세부내역,출처,확인,메모"]
        let day = DateFormatter()
        day.locale = Locale(identifier: "ko_KR")
        day.dateFormat = "yyyy-MM-dd"
        func esc(_ s: String?) -> String {
            let v = s ?? ""
            if v.contains(",") || v.contains("\"") || v.contains("\n") {
                return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return v
        }
        let plans = (try? ctx.fetch(FetchDescriptor<PlanBlock>(sortBy: [SortDescriptor(\.start)]))) ?? []
        for p in plans where !p.isCancelled {
            let mins = Int(p.end.timeIntervalSince(p.start) / 60)
            lines.append(["계획", day.string(from: p.start), Fmt.hm(p.start), Fmt.hm(p.end), "\(mins)",
                          esc(p.detail?.category?.name), esc(p.detail?.name ?? p.title), p.sourceRaw,
                          p.confirmation?.label ?? "", esc(p.note)].joined(separator: ","))
        }
        let actuals = (try? ctx.fetch(FetchDescriptor<ActualRecord>(sortBy: [SortDescriptor(\.start)]))) ?? []
        for a in actuals {
            let end = a.end ?? Date()
            let mins = Int(end.timeIntervalSince(a.start) / 60)
            lines.append(["실제", day.string(from: a.start), Fmt.hm(a.start), a.end.map(Fmt.hm) ?? "기록 중", "\(mins)",
                          esc(a.detail?.category?.name), esc(a.detail?.name), a.sourceRaw, "", esc(a.note)].joined(separator: ","))
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plan-actual-\(stamp.string(from: Date())).csv")
        try ("\u{FEFF}" + lines.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
