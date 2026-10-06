import SwiftData
import SwiftUI
import UIKit

enum SettingsRoute: Hashable {
    case categories, archive, timetables, calendar, todos
}

/// 탭 5 · 설정 (18)
struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(SyncMonitor.self) private var sync
    @Environment(CalendarService.self) private var calendarService
    @Environment(HealthService.self) private var health
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query(sort: \Timetable.sortOrder) private var timetables: [Timetable]
    @Query private var links: [CalendarLink]
    @AppStorage(PersistenceController.iCloudKey) private var iCloudEnabled = true

    @State private var showDayRange = false
    @State private var showTheme = false
    @State private var export: ExportFile?
    @State private var confirmDeleteAll = false
    @State private var showRestartNote = false

    private var prefs: AppPreferences { prefsList.first ?? DataStore.preferences(ctx) }

    var body: some View {
        NavigationStack {
            List {
                Section("하루") {
                    Button { showDayRange = true } label: {
                        row("하루 시작 · 끝", value: rangeText)
                    }
                    Picker("하루 마감 알림", selection: binding(\.closeReminderOffset)) {
                        Text("끄기").tag(0)
                        Text("끝나기 30분 전").tag(30)
                        Text("끝나기 1시간 전").tag(60)
                        Text("끝나기 2시간 전").tag(120)
                    }
                }

                Section("기록 구조") {
                    NavigationLink(value: SettingsRoute.categories) {
                        row("카테고리 · 세부내역", value: "\(activeCount)개 · 보관 \(archivedCount)")
                    }
                    Button { showTheme = true } label: {
                        row("색 테마", value: ColorThemes.theme(prefs.activeThemeID).name)
                    }
                    NavigationLink(value: SettingsRoute.timetables) {
                        row("시간표", value: PlanResolver.activeTimetable(for: Date(), in: timetables).map { "\($0.name) 적용 중" } ?? "없음")
                    }
                }

                Section("연동") {
                    NavigationLink(value: SettingsRoute.calendar) {
                        row("캘린더", value: calendarValue)
                    }
                    NavigationLink(value: SettingsRoute.todos) {
                        row("미리알림", value: reminderValue)
                    }
                    Toggle(isOn: Binding(get: { prefs.healthEnabled }, set: { on in
                        prefs.healthEnabled = on
                        prefs.updatedAt = Date()
                        DataStore.save(ctx)
                        if on { Task { await health.requestAuthorization() } }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("건강 앱")
                            Text(health.isAvailable ? "수면 · 운동 읽기" : "이 기기에서는 쓸 수 없어요")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .disabled(!health.isAvailable)
                }

                Section("알림 · 동기화") {
                    Toggle("계획이 끝나면 “했나요?”", isOn: binding(\.askWhenDone))
                    Toggle(isOn: Binding(get: { iCloudEnabled }, set: { iCloudEnabled = $0; showRestartNote = true })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud 동기화")
                            Text("\(sync.statusText) · \(DataStore.deviceName)")
                                .font(.caption)
                                .foregroundStyle(sync.lastError == nil ? Palette.inkSecondary : Palette.divergeInk)
                        }
                    }
                }

                Section {
                    Button {
                        do { export = ExportFile(url: try CSVExporter.export(ctx: ctx)) }
                        catch { toasts.show("내보내지 못했어요", symbol: "exclamationmark.triangle") }
                    } label: {
                        Label("백업 · CSV 내보내기", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("모든 기록 삭제", systemImage: "trash")
                    }
                    .foregroundStyle(Palette.destructive)
                } footer: {
                    Text("내 iCloud 안에서만 기기끼리 동기화돼요. 별도 계정이나 서버는 없어요.")
                }
            }
            .tint(Palette.ink)
            .foregroundStyle(Palette.ink)
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle("설정")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .categories: CategoriesView()
                case .archive: ArchiveView()
                case .timetables: TimetablesView()
                case .calendar: CalendarSyncView()
                case .todos: TodosView()
                }
            }
            .sheet(isPresented: $showDayRange) { DayRangeSheet() }
            .sheet(isPresented: $showTheme) { ColorPickerSheet(category: nil) }
            .sheet(item: $export) { file in ActivityView(items: [file.url]).ignoresSafeArea() }
            .confirmationDialog("모든 기록을 지울까요?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("모든 기록 삭제", role: .destructive) {
                    DataStore.deleteAllRecords(ctx)
                    toasts.show("모든 기록을 지웠어요", symbol: "trash")
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("계획 · 실제 기록 · 하루 마감이 iCloud와 모든 기기에서 지워지고 되돌릴 수 없어요. 카테고리와 시간표는 남아요.")
            }
            .alert("앱을 다시 열면 적용돼요", isPresented: $showRestartNote) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(iCloudEnabled ? "다시 켜면 이 기기의 데이터와 iCloud의 데이터를 합쳐요." : "기기에 있는 데이터는 그대로 두고 동기화만 멈춰요.")
            }
            .toastHost()
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Spacer()
            Text(value).foregroundStyle(Palette.inkSecondary).lineLimit(1)
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(get: { prefs[keyPath: keyPath] }, set: { v in
            prefs[keyPath: keyPath] = v
            prefs.updatedAt = Date()
            DataStore.save(ctx)
        })
    }

    private var rangeText: String {
        let c = DayClock(prefs)
        return "\(Fmt.minuteLabel(c.startMinute)) – \(c.endsNextDay ? "다음 날 " : "")\(Fmt.minuteLabel(c.endMinute))"
    }

    private var activeCount: Int { categories.filter { $0.archivedAt == nil }.count }
    private var archivedCount: Int {
        categories.filter { $0.archivedAt != nil }.count
            + categories.flatMap { $0.details ?? [] }.filter { $0.archivedAt != nil }.count
    }

    private var calendarValue: String {
        if !calendarService.hasEventAccess { return calendarService.eventAccessDenied ? "권한 없음" : "꺼짐" }
        let n = links.filter { $0.mode == .importAs && $0.detail != nil }.count
        return prefs.showCalendarEvents ? "\(n)개 연결" : "표시 안 함"
    }

    private var reminderValue: String {
        if !calendarService.hasReminderAccess { return calendarService.reminderAccessDenied ? "권한 없음" : "꺼짐" }
        return prefs.reminderListKeys.isEmpty ? "모든 목록" : prefs.reminderListKeys.joined(separator: " · ")
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 18 내부 · 하루 시작 · 끝 — 휠 2개, 15분 단위
struct DayRangeSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    @State private var loaded = false

    private var startMinute: Int { DayClock.minuteOfDay(start) / 15 * 15 }
    private var endMinuteRaw: Int { DayClock.minuteOfDay(end) / 15 * 15 }
    private var nextDay: Bool { endMinuteRaw <= startMinute }
    private var length: Int { (nextDay ? endMinuteRaw + 1440 : endMinuteRaw) - startMinute }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("시작").font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
                        DatePicker("시작", selection: $start, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                    }
                    VStack(spacing: 4) {
                        Text(nextDay ? "끝 · 다음 날" : "끝").font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
                        DatePicker("끝", selection: $end, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                    }
                }
                Text("\(Fmt.minuteLabel(startMinute)) – \(nextDay ? "다음 날 " : "")\(Fmt.minuteLabel(endMinuteRaw)) · \(Fmt.duration(length))")
                    .font(.headline)
                    .monospacedDigit()
                Text("타임라인 높이, 하루 마감 알림, 일치율, 주간 집계가 이 경계를 따라요. 바꾸면 오늘 이후부터 적용돼요.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Spacer()
            }
            .padding(.top, 8)
            .navigationTitle("하루 시작 · 끝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { save() } }
            }
        }
        .appSheet([.medium, .large])
        .onAppear {
            UIDatePicker.appearance().minuteInterval = 15
            guard !loaded else { return }
            loaded = true
            let p = DataStore.preferences(ctx)
            let c = DayClock(p)
            let midnight = DayClock.calendar.startOfDay(for: Date())
            start = midnight.addingTimeInterval(Double(c.startMinute) * 60)
            end = midnight.addingTimeInterval(Double(c.endMinute % 1440) * 60)
        }
        .onDisappear { UIDatePicker.appearance().minuteInterval = 1 }
    }

    private func save() {
        let p = DataStore.preferences(ctx)
        // 오늘이 이미 지나간 날은 원래 범위를 DaySummary에 남겨둬요.
        let old = DayClock(p)
        let today = old.logicalDay(for: Date())
        let yesterdayKey = DayClock.dayKey(DayClock.addDays(-1, to: today))
        if DataStore.summary(dayKey: yesterdayKey, ctx: ctx) == nil {
            ctx.insert(DaySummary(dayKey: yesterdayKey, rangeStartMinute: old.startMinute, rangeEndMinute: old.endMinute))
        }
        p.dayStartMinute = startMinute
        p.dayEndMinute = startMinute + max(15, min(1440, length))
        p.updatedAt = Date()
        DataStore.save(ctx)
        dismiss()
    }
}
