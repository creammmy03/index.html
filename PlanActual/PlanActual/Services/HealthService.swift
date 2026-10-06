import Foundation
import HealthKit
import Observation

struct HealthEvent: Identifiable, Hashable {
    enum Kind: String { case sleep, workout }
    let id = UUID()
    let kind: Kind
    let title: String
    let start: Date
    let end: Date
    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// 수면 · 운동 읽기 (하루 마감, 빈 시간 채우기의 단서).
@MainActor
@Observable
final class HealthService {
    @ObservationIgnored private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
            HKQuantityType(.stepCount)
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            return false
        }
    }

    func events(in interval: DateInterval) async -> [HealthEvent] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        var out: [HealthEvent] = []

        let sleepQuery = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let sleepSamples = ((try? await sleepQuery.result(for: store)) ?? []).filter { asleep.contains($0.value) }
        var merged: [(Date, Date)] = []
        for s in sleepSamples {
            if let last = merged.last, s.startDate <= last.1.addingTimeInterval(30 * 60) {
                merged[merged.count - 1].1 = max(last.1, s.endDate)
            } else {
                merged.append((s.startDate, s.endDate))
            }
        }
        out += merged.map { HealthEvent(kind: .sleep, title: "수면", start: $0.0, end: $0.1) }

        let workoutQuery = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = (try? await workoutQuery.result(for: store)) ?? []
        out += workouts.map { HealthEvent(kind: .workout, title: Self.name(for: $0.workoutActivityType), start: $0.startDate, end: $0.endDate) }
        return out.sorted { $0.start < $1.start }
    }

    static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "러닝"
        case .walking: return "걷기"
        case .cycling: return "사이클"
        case .hiking: return "등산"
        case .swimming: return "수영"
        case .yoga: return "요가"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "헬스"
        case .highIntensityIntervalTraining: return "인터벌"
        case .pilates: return "필라테스"
        default: return "운동"
        }
    }
}
