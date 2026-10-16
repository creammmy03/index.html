import Foundation
import SwiftData

/// SwiftData + CloudKit(개인 DB). 저장소는 App Group 컨테이너에 둬요.
enum PersistenceController {
    static let iCloudKey = "iCloudSyncEnabled"

    static var iCloudEnabled: Bool {
        UserDefaults.standard.object(forKey: iCloudKey) as? Bool ?? true
    }

    static var cloudKitContainerID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerID") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    static func makeContainer() -> ModelContainer {
        let schema = AppSchema.schema
        let groupID = SharedConfig.appGroupID
        let hasGroup = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
        let group: ModelConfiguration.GroupContainer = hasGroup ? .identifier(groupID) : .none

        // iCloud 엔타이틀먼트가 없거나(무료 계정 · 서명 안 한 빌드) iCloud에 로그인하지 않았으면 토큰이 nil이에요.
        // 이때 CloudKit을 켜면 CKContainer가 앱을 바로 멈추게 하니, 기기 안 저장소로 가요.
        let iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
        if iCloudEnabled, iCloudAvailable, let cloudID = cloudKitContainerID {
            let config = ModelConfiguration("PlanActual", schema: schema, groupContainer: group, cloudKitDatabase: .private(cloudID))
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }
        // iCloud를 끄면 기기에 있는 데이터는 그대로 두고 동기화만 멈춰요.
        let local = ModelConfiguration("PlanActual", schema: schema, groupContainer: group, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return container
        }
        let memory = ModelConfiguration("PlanActualMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("데이터 저장소를 열 수 없어요: \(error)")
        }
    }
}
