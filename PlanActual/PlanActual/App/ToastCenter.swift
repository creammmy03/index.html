import Foundation
import Observation

/// 기록 토스트 + 실행 취소. 4초 노출, 앱이 백그라운드면 시간이 멈춰요.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let symbol: String
        let undo: (() -> Void)?
    }

    private(set) var current: Toast?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var remaining: TimeInterval = 4
    @ObservationIgnored private var shownAt = Date()

    func show(_ message: String, symbol: String = "checkmark", undo: (() -> Void)? = nil) {
        current = Toast(message: message, symbol: symbol, undo: undo)
        remaining = 4
        schedule()
    }

    func performUndo() {
        current?.undo?()
        dismiss()
    }

    func dismiss() {
        task?.cancel()
        current = nil
    }

    func pause() {
        guard current != nil else { return }
        task?.cancel()
        remaining = max(0.5, remaining - Date().timeIntervalSince(shownAt))
    }

    func resume() {
        guard current != nil else { return }
        schedule()
    }

    private func schedule() {
        task?.cancel()
        shownAt = Date()
        let wait = remaining
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }
}
