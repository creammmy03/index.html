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

        if iCloudEnabled, let cloudID = cloudKitContainerID {
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
