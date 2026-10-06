import CoreData
import Foundation
import Observation

/// iCloud 동기화 상태 — 로딩 표시는 하지 않고, 실패했을 때만 이유를 보여줘요.
@MainActor
@Observable
final class SyncMonitor {
    private(set) var lastSuccess: Date?
    private(set) var lastError: String?
    private(set) var isSignedIn: Bool = FileManager.default.ubiquityIdentityToken != nil
    @ObservationIgnored var onImport: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }
            let succeeded = event.succeeded
            let isImport = event.type == .import
            let message = event.error.map(Self.describe)
            Task { @MainActor in
                guard let self else { return }
                if succeeded {
                    self.lastSuccess = Date()
                    self.lastError = nil
                    if isImport { self.onImport?() }
                } else {
                    self.lastError = message
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isSignedIn = FileManager.default.ubiquityIdentityToken != nil }
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("quota") { return "iCloud 용량이 부족해요" }
        if text.localizedCaseInsensitiveContains("network") || text.localizedCaseInsensitiveContains("offline") { return "네트워크에 연결되지 않았어요" }
        if text.localizedCaseInsensitiveContains("account") { return "iCloud에 로그인되어 있지 않아요" }
        return "동기화하지 못했어요"
    }

    var statusText: String {
        if !PersistenceController.iCloudEnabled { return "꺼짐 · 이 기기에만 저장" }
        if !isSignedIn { return "iCloud 로그아웃 · 이 기기에만 저장" }
        if let lastError { return lastError }
        guard let lastSuccess else { return "켜짐" }
        let seconds = Date().timeIntervalSince(lastSuccess)
        if seconds < 90 { return "방금 동기화" }
        if seconds < 3600 { return "\(Int(seconds / 60))분 전 동기화" }
        return "\(Fmt.hm(lastSuccess)) 동기화"
    }
}
