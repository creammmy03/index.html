import SwiftData
import SwiftUI

enum DeleteTarget: Identifiable {
    case detail(ActivityDetail)
    case category(ActivityCategory)

    var id: UUID {
        switch self {
        case .detail(let d): return d.id
        case .category(let c): return c.id
        }
    }
}

/// 09 · 카테고리 › 세부내역 · 밀어서 보관/삭제
struct CategoriesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query private var weekActuals: [ActualRecord]

    @State private var expanded: Set<UUID> = []
    @State private var deleteTarget: DeleteTarget?
    @State private var colorTarget: ActivityCategory?
    @State private var newDetailFor: ActivityCategory?
    @State private var renameDetail: ActivityDetail?
    @State private var renameCategory: ActivityCategory?
    @State private var showNewCategory = false
    @State private var text = ""
    @State private var archiveTick = 0
    @State private var didExpand = false

    init() {
        let s = DayClock.weekStart(for: Date())
        _weekActuals = Query(filter: #Predicate<ActualRecord> { $0.start >= s })
    }

    private var active: [ActivityCategory] { categories.filter { $0.archivedAt == nil } }

    private var archivedCount: Int {
        categories.filter { $0.archivedAt != nil }.count
            + active.flatMap { $0.details ?? [] }.filter { $0.archivedAt != nil }.count
    }

    private var weekMinutes: [UUID: Int] {
        var m: [UUID: Int] = [:]
        for r in weekActuals {
            guard let d = r.detail else { continue }
            let mins = Int(((r.end ?? Date()).timeIntervalSince(r.start)) / 60)
            m[d.id, default: 0] += mins
            if let c = d.category { m[c.id, default: 0] += mins }
        }
        return m
    }

    var body: some View {
        let totals = weekMinutes
        List {
            Section {
                HStack {
                    Text("카테고리")
                    Spacer()
                    Text("이번 주 합계")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
                .listRowBackground(Color.clear)
            }
            ForEach(Array(active.enumerated()), id: \.element.id) { index, c in
                Section {
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(c.id) }, set: { on in
                        if on { expanded.insert(c.id) } else { expanded.remove(c.id) }
                    })) {
                        ForEach(c.activeDetails) { d in
                            Button {
                                text = d.name
                                renameDetail = d
                            } label: {
                                HStack {
                                    Text(d.name).foregroundStyle(Palette.ink)
                                    if !(d.calendarLinks ?? []).isEmpty {
                                        Image(systemName: "calendar").font(.caption).foregroundStyle(Palette.inkSecondary)
                                    }
                                    Spacer()
                                    Text(Fmt.clock(totals[d.id] ?? 0)).monospacedDigit().foregroundStyle(Palette.inkSecondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    DataStore.archive(d)
                                    DataStore.save(ctx)
                                    archiveTick += 1
                                    toasts.show("‘\(d.name)’을 보관했어요", symbol: "archivebox") {
                                        DataStore.restore(d)
                                        DataStore.save(ctx)
                                    }
                                } label: { Label("보관", systemImage: "archivebox") }
                                .tint(.gray)
                                Button {
                                    deleteTarget = .detail(d)
                                } label: { Label("삭제", systemImage: "trash") }
                                .tint(Palette.destructive)
                            }
                        }
                        Button {
                            text = ""
                            newDetailFor = c
                        } label: {
                            Label("세부내역 추가", systemImage: "plus").foregroundStyle(Palette.inkSecondary)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Button { colorTarget = c } label: { ColorDot(hex: c.colorHex, size: 14).frame(width: 30, height: 30) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("\(c.name) 색 바꾸기")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.headline)
                                if !expanded.contains(c.id) {
                                    Text(c.activeDetails.map(\.name).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(Fmt.clock(totals[c.id] ?? 0)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            Menu {
                                Button { text = c.name; renameCategory = c } label: { Label("이름 바꾸기", systemImage: "pencil") }
                                Button { colorTarget = c } label: { Label("색 바꾸기", systemImage: "paintpalette") }
                                if index > 0 { Button { move(c, by: -1) } label: { Label("위로", systemImage: "arrow.up") } }
                                if index < active.count - 1 { Button { move(c, by: 1) } label: { Label("아래로", systemImage: "arrow.down") } }
                                Button {
                                    DataStore.archive(c)
                                    DataStore.save(ctx)
                                    toasts.show("‘\(c.name)’을 보관했어요", symbol: "archivebox") {
                                        DataStore.restore(c)
                                        DataStore.save(ctx)
                                    }
                                } label: { Label("보관", systemImage: "archivebox") }
                                Button(role: .destructive) { deleteTarget = .category(c) } label: { Label("삭제", systemImage: "trash") }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 32, height: 32)
                            }
                            .accessibilityLabel("\(c.name) 더 보기")
                        }
                    }
                    .tint(Palette.inkSecondary)
                }
            }
            Section {
                Button {
                    text = ""
                    showNewCategory = true
                } label: {
                    Label("카테고리 추가", systemImage: "plus")
                }
                NavigationLink(value: SettingsRoute.archive) {
                    HStack {
                        Label("보관함", systemImage: "archivebox")
                        Spacer()
                        Text("\(archivedCount)").foregroundStyle(Palette.inkSecondary)
                    }
                }
            } footer: {
                Text("왼쪽으로 밀어 보관하거나 삭제해요. 보관은 기록을 남기고 숨기기만, 삭제는 기록까지 정리해요.")
            }
        }
        .foregroundStyle(Palette.ink)
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("카테고리와 세부내역")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .medium), trigger: archiveTick)
        .onAppear {
            guard !didExpand else { return }
            didExpand = true
            if let first = active.first { expanded.insert(first.id) }
        }
        .sheet(item: $deleteTarget) { t in DeleteConfirmSheet(target: t) }
        .sheet(item: $colorTarget) { c in ColorPickerSheet(category: c) }
        .alert("새 세부내역", isPresented: Binding(get: { newDetailFor != nil }, set: { if !$0 { newDetailFor = nil } })) {
            TextField("이름", text: $text)
            Button("취소", role: .cancel) {}
            Button("추가") {
                let name = text.trimmingCharacters(in: .whitespaces)
                if let c = newDetailFor, !name.isEmpty {
                    DataStore.makeDetail(name: name, in: c, ctx: ctx)
                    DataStore.save(ctx)
                }
            }
        }
        .alert("세부내역 이름", isPresented: Binding(get: { renameDetail != nil }, set: { if !$0 { renameDetail = nil } })) {
            TextField("이름", text: $text)
            Button("취소", role: .cancel) {}
            Button("저장") {
                let name = text.trimmingCharacters(in: .whitespaces)
                if let d = renameDetail, !name.isEmpty { d.name = name; d.updatedAt = Date(); DataStore.save(ctx) }
            }
        }
        .alert("카테고리 이름", isPresented: Binding(get: { renameCategory != nil }, set: { if !$0 { renameCategory = nil } })) {
            TextField("이름", text: $text)
            Button("취소", role: .cancel) {}
            Button("저장") {
                let name = text.trimmingCharacters(in: .whitespaces)
                if let c = renameCategory, !name.isEmpty { c.name = name; c.updatedAt = Date(); DataStore.save(ctx) }
            }
        }
        .alert("새 카테고리", isPresented: $showNewCategory) {
            TextField("이름", text: $text)
            Button("취소", role: .cancel) {}
            Button("추가") {
                let name = text.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let prefs = DataStore.preferences(ctx)
                let theme = ColorThemes.theme(prefs.activeThemeID)
                let used = Set(categories.map(\.colorHex))
                let hex = theme.colors.first { !used.contains($0) } ?? theme.colors[categories.count % theme.colors.count]
                let c = DataStore.makeCategory(name: name, colorHex: hex, ctx: ctx)
                DataStore.save(ctx)
                expanded.insert(c.id)
            }
        } message: {
            Text("색은 지금 테마에서 골라두고, 나중에 바꿀 수 있어요.")
        }
    }

    private func move(_ c: ActivityCategory, by delta: Int) {
        var list = active
        guard let i = list.firstIndex(where: { $0.id == c.id }) else { return }
        let j = i + delta
        guard j >= 0 && j < list.count else { return }
        list.swapAt(i, j)
        for (n, cat) in list.enumerated() { cat.sortOrder = n; cat.updatedAt = Date() }
        DataStore.save(ctx)
    }
}

/// 10 · 세부내역 삭제 · 기록 처리 (medium)
struct DeleteConfirmSheet: View {
    let target: DeleteTarget
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @State private var moveRecords = true
    @State private var moveTo: ActivityDetail?
    @State private var showPicker = false

    private var details: [ActivityDetail] {
        switch target {
        case .detail(let d): return [d]
        case .category(let c): return c.details ?? []
        }
    }

    private var name: String {
        switch target {
        case .detail(let d): return d.name
        case .category(let c): return c.name
        }
    }

    private var path: String {
        switch target {
        case .detail(let d): return d.pathName
        case .category(let c): return "\(c.name) · 세부내역 \((c.details ?? []).count)개"
        }
    }

    private var recordedMinutes: Int {
        details.flatMap { $0.actuals ?? [] }.reduce(0) { $0 + Int((($1.end ?? Date()).timeIntervalSince($1.start)) / 60) }
    }

    private var futurePlans: Int {
        let now = Date()
        return details.flatMap { $0.plans ?? [] }.filter { $0.start > now }.count
    }

    private var hasCalendarLink: Bool { details.contains { !($0.calendarLinks ?? []).isEmpty } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("‘\(name)’을 삭제할까요?").font(.title3.bold())
                        Text("\(path) · 누적 기록 \(Fmt.duration(recordedMinutes)) · 앞으로의 계획 \(futurePlans)개")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if hasCalendarLink {
                        Label("캘린더가 연결되어 있어요. 삭제하면 그 캘린더는 ‘가져오지 않음’으로 바뀌어요.", systemImage: "calendar.badge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(Palette.divergeInk)
                            .padding(12)
                            .background(Palette.divergeTint, in: .rect(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("지난 기록은").font(.subheadline.weight(.semibold)).padding(.bottom, 8)
                        radio(selected: moveRecords, title: "다른 세부내역으로 옮기기", subtitle: moveTo?.pathName ?? "옮길 곳 고르기") {
                            moveRecords = true
                            showPicker = true
                        }
                        Divider()
                        radio(selected: !moveRecords, title: "기록도 함께 지우기", subtitle: "하루 마감·목표·인사이트에서도 빠지고 되돌릴 수 없어요") {
                            moveRecords = false
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.surface, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))

                    Button {
                        archiveInstead()
                    } label: {
                        VStack(spacing: 2) {
                            Text("지우지 말고 보관하기").font(.subheadline.weight(.semibold))
                            Text("기록은 그대로, 선택지에서만 숨겨요").font(.caption).foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Palette.ground, in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.pressable)
                    .foregroundStyle(Palette.ink)

                    LongPressDeleteButton(title: "길게 눌러 삭제") { performDelete() }
                        .disabled(moveRecords && moveTo == nil)
                        .opacity(moveRecords && moveTo == nil ? 0.5 : 1)

                    Button("취소") { dismiss() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .appSheet([.medium, .large])
        .onAppear {
            if moveTo == nil {
                let excluded = Set(details.map(\.id))
                let sameCategory: ActivityCategory? = {
                    if case .detail(let d) = target { return d.category }
                    return nil
                }()
                moveTo = sameCategory?.activeDetails.first { !excluded.contains($0.id) }
            }
        }
        .sheet(isPresented: $showPicker) {
            DetailPickerSheet(title: "옮길 곳", confirmTitle: "여기로 옮기기", initial: moveTo) { d in
                if !details.contains(where: { $0.id == d.id }) { moveTo = d }
            }
        }
    }

    private func radio(selected: Bool, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(Palette.inkSecondary)
                }
                Spacer()
            }
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    private func archiveInstead() {
        switch target {
        case .detail(let d): DataStore.archive(d)
        case .category(let c): DataStore.archive(c)
        }
        DataStore.save(ctx)
        toasts.show("‘\(name)’을 보관했어요", symbol: "archivebox")
        dismiss()
    }

    private func performDelete() {
        guard !(moveRecords && moveTo == nil) else { return }
        let label = name
        switch target {
        case .detail(let d): DataStore.delete(d, moveTo: moveRecords ? moveTo : nil, ctx: ctx)
        case .category(let c): DataStore.delete(c, moveTo: moveRecords ? moveTo : nil, ctx: ctx)
        }
        toasts.show("‘\(label)’을 삭제했어요", symbol: "trash")
        dismiss()
    }
}

/// 11 · 보관함
struct ArchiveView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    private var archivedCategories: [ActivityCategory] { categories.filter { $0.archivedAt != nil } }
    private var archivedDetails: [ActivityDetail] {
        categories.filter { $0.archivedAt == nil }.flatMap { $0.details ?? [] }.filter { $0.archivedAt != nil }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                Text("보관한 항목은 계획과 기록의 선택지에서만 숨겨져요. 지난 기록과 통계에는 그대로 남아요.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .listRowBackground(Color.clear)
            }
            if !archivedCategories.isEmpty {
                Section("카테고리") {
                    ForEach(archivedCategories) { c in
                        row(title: c.name, prefix: nil, hex: c.colorHex,
                            subtitle: "세부내역 \((c.details ?? []).count)개 · 누적 \(Fmt.clock(minutes(c.details ?? []))) · \(archivedText(c.archivedAt))") {
                            DataStore.restore(c)
                            DataStore.save(ctx)
                        }
                    }
                }
            }
            Section("세부내역") {
                if archivedDetails.isEmpty {
                    Text("보관한 세부내역이 없어요").foregroundStyle(Palette.inkSecondary)
                }
                ForEach(archivedDetails) { d in
                    row(title: d.name, prefix: "\(d.category?.name ?? "") ›", hex: d.colorHex,
                        subtitle: "누적 \(Fmt.clock(minutes([d]))) · \(archivedText(d.archivedAt))") {
                        DataStore.restore(d)
                        DataStore.save(ctx)
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(get: { prefsList.first?.includeArchivedInStats ?? true }, set: { v in
                    let p = DataStore.preferences(ctx)
                    p.includeArchivedInStats = v
                    p.updatedAt = Date()
                    DataStore.save(ctx)
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("통계에 보관 항목 포함")
                        Text("끄면 인사이트·목표에서도 빠져요").font(.caption).foregroundStyle(Palette.inkSecondary)
                    }
                }
                .tint(Palette.ink)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("보관함")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func minutes(_ details: [ActivityDetail]) -> Int {
        details.flatMap { $0.actuals ?? [] }.reduce(0) { $0 + Int((($1.end ?? Date()).timeIntervalSince($1.start)) / 60) }
    }

    private func archivedText(_ date: Date?) -> String {
        guard let date else { return "" }
        if Date().timeIntervalSince(date) < 3600 { return "방금 보관" }
        return "\(Fmt.monthDay(date)) 보관"
    }

    private func row(title: String, prefix: String?, hex: String, subtitle: String, restore: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            ColorDot(hex: hex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let prefix { Text(prefix).foregroundStyle(Palette.inkSecondary) }
                    Text(title).font(.subheadline.weight(.semibold))
                }
                Text(subtitle).font(.caption).foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Button("복원", action: restore)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(Palette.ink)
        }
    }
}
