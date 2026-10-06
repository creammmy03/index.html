import EventKit
import SwiftData
import SwiftUI

/// 미리알림 하나를 화면용으로
struct TodoRow: Identifiable {
    let reminder: EKReminder
    var id: String { reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier }
    var title: String { reminder.title ?? "제목 없음" }
    var listTitle: String { reminder.calendar?.title ?? "" }
    var due: Date? {
        guard let c = reminder.dueDateComponents else { return nil }
        return DayClock.calendar.date(from: c)
    }
    var hasTime: Bool { reminder.dueDateComponents?.hour != nil }

    var dueText: String? {
        guard let due else { return nil }
        let cal = DayClock.calendar
        let today = cal.startOfDay(for: Date())
        let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: due)).day ?? 0
        let time = hasTime ? " \(Fmt.hm(due))" : ""
        if days < 0 { return "\(Fmt.monthDay(due)) · 지남" }
        if days == 0 { return hasTime ? "오늘\(time)" : "오늘까지" }
        if days <= 7 { return "\(Fmt.monthDay(due)) · D-\(days)" }
        return Fmt.monthDay(due)
    }
}

@MainActor
@Observable
final class TodoStore {
    var incomplete: [TodoRow] = []
    var completed: [TodoRow] = []
    var lists: [EKCalendar] = []

    func reload(_ service: CalendarService, keys: [String], filter: String?) async {
        guard service.hasReminderAccess else {
            incomplete = []
            completed = []
            lists = []
            return
        }
        lists = service.reminderLists()
        var chosen = keys.isEmpty ? lists : lists.filter { keys.contains($0.title) }
        if let filter { chosen = chosen.filter { $0.title == filter } }
        if chosen.isEmpty { chosen = keys.isEmpty ? lists : [] }
        let open = await service.fetchReminders(lists: chosen.isEmpty ? nil : chosen, completed: false)
        let done = await service.fetchReminders(lists: chosen.isEmpty ? nil : chosen, completed: true)
        incomplete = open.map(TodoRow.init(reminder:)).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        completed = done.map(TodoRow.init(reminder:))
    }
}

/// 05 아래 · 할 일 요약
struct TodoSummaryCard: View {
    let onOpen: () -> Void
    @Environment(CalendarService.self) private var calendarService
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @Query(filter: #Predicate<PlanBlock> { $0.sourceRaw == "todo" }) private var placed: [PlanBlock]
    @State private var store = TodoStore()
    @State private var placing: TodoRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("할 일").font(.title3.bold())
                Spacer()
                Button("전체 보기", action: onOpen).font(.subheadline.weight(.semibold))
            }
            if !calendarService.hasReminderAccess {
                PermissionCard(
                    title: "미리알림을 연결해요",
                    message: calendarService.reminderAccessDenied ? "설정에서 미리알림 접근을 켜면 할 일을 타임라인에 배치할 수 있어요." : "할 일을 보고, 타임라인에 배치하고, 완료를 양쪽에 맞춰요.",
                    buttonTitle: calendarService.reminderAccessDenied ? "설정 열기" : "연결하기"
                ) {
                    if calendarService.reminderAccessDenied { calendarService.openSettings() }
                    else { Task { await calendarService.requestReminderAccess() } }
                }
            } else if store.incomplete.isEmpty {
                Text("남은 할 일이 없어요").font(.footnote).foregroundStyle(Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.incomplete.prefix(4)) { row in
                        TodoRowView(row: row, placed: placed.first { $0.ekExternalID == row.id && $0.end > Date() }) {
                            try? calendarService.setCompleted(row.reminder, true)
                        } onPlace: { placing = row }
                        if row.id != store.incomplete.prefix(4).last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(Palette.surface, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.7)))
            }
        }
        .padding(.top, 10)
        .task(id: calendarService.revision) {
            await store.reload(calendarService, keys: prefsList.first?.reminderListKeys ?? [], filter: nil)
        }
        .sheet(item: $placing) { row in PlaceTodoSheet(row: row) }
    }
}

struct TodoRowView: View {
    let row: TodoRow
    let placed: PlanBlock?
    var linkedDetail: ActivityDetail? = nil
    let onComplete: () -> Void
    let onPlace: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: row.reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.reminder.isCompleted ? Palette.ink : Palette.inkTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.pressable)
            .padding(.leading, -10)
            .accessibilityLabel(row.reminder.isCompleted ? "완료 취소" : "완료")
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(row.reminder.isCompleted)
                HStack(spacing: 6) {
                    if let due = row.dueText { Text(due) }
                    if !row.listTitle.isEmpty { Text("· \(row.listTitle)") }
                }
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                if let d = linkedDetail ?? placed?.detail {
                    HStack(spacing: 4) {
                        ColorDot(hex: d.colorHex, size: 7)
                        Text(d.pathName).font(.caption)
                    }
                    .foregroundStyle(Palette.inkSecondary)
                }
                if let p = placed {
                    Label("\(Fmt.weekdayShort(p.start)) \(Fmt.hm(p.start)) 배치됨", systemImage: "calendar.badge.checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                } else if !row.reminder.isCompleted {
                    Button("타임라인에 배치", action: onPlace)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Palette.ground, in: .capsule)
                        .buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
    }
}

/// 14 · 할 일 · 미리알림 연동
struct TodosView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.modelContext) private var ctx
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]
    @Query(filter: #Predicate<PlanBlock> { $0.sourceRaw == "todo" }) private var placed: [PlanBlock]
    @Query private var reminderLinks: [ReminderLink]
    @State private var store = TodoStore()
    @State private var filter: String?
    @State private var showCompleted = false
    @State private var placing: TodoRow?
    @State private var linking: TodoRow?
    @State private var showLists = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !calendarService.hasReminderAccess {
                    PermissionCard(
                        title: "미리알림 접근이 필요해요",
                        message: "할 일을 읽고 완료 상태를 맞추려면 미리알림 전체 접근을 허용해주세요.",
                        buttonTitle: calendarService.reminderAccessDenied ? "설정 열기" : "허용하기"
                    ) {
                        if calendarService.reminderAccessDenied { calendarService.openSettings() }
                        else { Task { await calendarService.requestReminderAccess() } }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            OutlineChip(title: "전체", filled: filter == nil) { filter = nil }
                            ForEach(visibleLists, id: \.calendarIdentifier) { l in
                                OutlineChip(title: l.title, filled: filter == l.title) { filter = l.title }
                            }
                            OutlineChip(title: "목록 연결", symbol: "link") { showLists = true }
                        }
                    }
                    .scrollClipDisabled()

                    ForEach(sections, id: \.0) { title, rows in
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: title)
                            VStack(spacing: 0) {
                                ForEach(rows) { row in
                                    TodoRowView(row: row, placed: placedBlock(row), linkedDetail: link(for: row)?.detail) {
                                        try? calendarService.setCompleted(row.reminder, !row.reminder.isCompleted)
                                    } onPlace: { placing = row }
                                    .contextMenu {
                                        Button { linking = row } label: { Label("카테고리 지정", systemImage: "tag") }
                                        Button { placing = row } label: { Label("타임라인에 배치", systemImage: "calendar.badge.plus") }
                                    }
                                    if row.id != rows.last?.id { Divider() }
                                }
                            }
                            .padding(.horizontal, 14)
                            .background(Palette.surface, in: .rect(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.7)))
                        }
                    }
                    if store.incomplete.isEmpty {
                        Text("남은 할 일이 없어요").font(.footnote).foregroundStyle(Palette.inkSecondary)
                    }

                    Button {
                        showCompleted.toggle()
                    } label: {
                        Label("완료한 항목 \(store.completed.count)개", systemImage: showCompleted ? "chevron.down" : "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Palette.inkSecondary)
                    if showCompleted {
                        VStack(spacing: 0) {
                            ForEach(store.completed) { row in
                                TodoRowView(row: row, placed: nil) {
                                    try? calendarService.setCompleted(row.reminder, false)
                                } onPlace: {}
                                Divider()
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Palette.surface, in: .rect(cornerRadius: 16))
                    }
                    Text("여기서 완료하면 미리알림에서도 완료돼요. 배치한 할 일에 쓴 시간은 지정한 세부내역에 쌓여요.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(20)
        }
        .background(Palette.ground)
        .navigationTitle("할 일")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("할 일").font(.headline)
                    Text("미리알림 · \(calendarService.revision > 0 ? "방금 동기화" : "연결됨")").font(.caption2).foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .task(id: "\(calendarService.revision)|\(filter ?? "")") {
            await store.reload(calendarService, keys: prefsList.first?.reminderListKeys ?? [], filter: filter)
        }
        .refreshable {
            await store.reload(calendarService, keys: prefsList.first?.reminderListKeys ?? [], filter: filter)
        }
        .sheet(item: $placing) { row in PlaceTodoSheet(row: row) }
        .sheet(item: $linking) { row in
            DetailPickerSheet(title: "카테고리 지정", message: "‘\(row.title)’에 쓴 시간이 이 세부내역에 쌓여요.", confirmTitle: "지정", initial: link(for: row)?.detail) { d in
                let l = link(for: row) ?? {
                    let n = ReminderLink(externalID: row.id)
                    ctx.insert(n)
                    return n
                }()
                l.detail = d
                DataStore.save(ctx)
            }
        }
        .sheet(isPresented: $showLists) { ReminderListsSheet() }
    }

    private var visibleLists: [EKCalendar] {
        let keys = prefsList.first?.reminderListKeys ?? []
        return keys.isEmpty ? store.lists : store.lists.filter { keys.contains($0.title) }
    }

    private func placedBlock(_ row: TodoRow) -> PlanBlock? {
        placed.first { $0.ekExternalID == row.id && $0.end > Date() }
    }

    private func link(for row: TodoRow) -> ReminderLink? {
        reminderLinks.first { $0.externalID == row.id }
    }

    private var sections: [(String, [TodoRow])] {
        let cal = DayClock.calendar
        let endToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let endWeek = DayClock.addDays(7, to: DayClock.weekStart(for: Date()))
        var today: [TodoRow] = [], week: [TodoRow] = [], later: [TodoRow] = [], none: [TodoRow] = []
        for r in store.incomplete {
            guard let due = r.due else { none.append(r); continue }
            if due < endToday { today.append(r) } else if due < endWeek { week.append(r) } else { later.append(r) }
        }
        return [("오늘", today), ("이번 주", week), ("나중", later), ("날짜 없음", none)].filter { !$0.1.isEmpty }
    }
}

/// 목록 연결 — 보여줄 미리알림 목록 고르기
struct ReminderListsSheet: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppPreferences.createdAt) private var prefsList: [AppPreferences]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(calendarService.reminderLists(), id: \.calendarIdentifier) { l in
                        let keys = prefsList.first?.reminderListKeys ?? []
                        let on = keys.isEmpty || keys.contains(l.title)
                        Button {
                            toggle(l.title, currentlyOn: on)
                        } label: {
                            HStack {
                                Circle().fill(Color(cgColor: l.cgColor)).frame(width: 10, height: 10)
                                Text(l.title).foregroundStyle(Palette.ink)
                                Spacer()
                                if on { Image(systemName: "checkmark").foregroundStyle(Palette.ink) }
                            }
                        }
                    }
                } footer: {
                    Text("고른 목록의 할 일만 보여줘요. 아무것도 고르지 않으면 모두 보여요.")
                }
            }
            .navigationTitle("목록 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .appSheet([.medium, .large])
    }

    private func toggle(_ title: String, currentlyOn: Bool) {
        let prefs = DataStore.preferences(ctx)
        var keys = prefs.reminderListKeys
        if keys.isEmpty { keys = calendarService.reminderLists().map(\.title) }
        if currentlyOn { keys.removeAll { $0 == title } } else { keys.append(title) }
        let all = calendarService.reminderLists().map(\.title)
        prefs.reminderListKeys = Set(keys) == Set(all) ? [] : keys
        prefs.updatedAt = Date()
        DataStore.save(ctx)
    }
}

/// 할 일을 타임라인에 배치 → PlanBlock(source: todo)
struct PlaceTodoSheet: View {
    let row: TodoRow
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @Query private var links: [ReminderLink]
    @State private var start = Date().roundedUp(toMinutes: 15)
    @State private var minutes = 60
    @State private var detail: ActivityDetail?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(row.title).font(.title3.bold())
                    VStack(spacing: 0) {
                        DatePicker("시작", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .padding(.horizontal, 14).frame(minHeight: 50)
                        Divider().padding(.leading, 14)
                        Stepper(value: $minutes, in: 15...480, step: 15) {
                            HStack {
                                Text("걸리는 시간")
                                Spacer()
                                Text(Fmt.duration(minutes)).monospacedDigit().foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 50)
                    }
                    .background(Palette.surface, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                    DetailPicker(selection: $detail)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button("\(Fmt.monthDayWeek(start)) \(Fmt.hm(start))에 배치") { place() }
                    .buttonStyle(.primary)
                    .disabled(detail == nil)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Palette.surface)
            }
            .navigationTitle("타임라인에 배치")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
        .appSheet([.large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            detail = links.first { $0.externalID == row.id }?.detail
            if let due = row.due, row.hasTime, due > Date() { start = due.addingTimeInterval(-3600) }
        }
    }

    private func place() {
        guard let detail else { return }
        let prefs = DataStore.preferences(ctx)
        let clock = DayClock(prefs)
        let day = clock.logicalDay(for: start)
        let b = DataStore.makePlan(detail: detail, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                                   source: .todo, dayKey: DayClock.dayKey(day), ctx: ctx)
        b.ekExternalID = row.id
        b.title = row.title
        if let l = links.first(where: { $0.externalID == row.id }) {
            l.detail = detail
        } else {
            let l = ReminderLink(externalID: row.id)
            ctx.insert(l)
            l.detail = detail
        }
        DataStore.save(ctx)
        toasts.show("‘\(row.title)’을 \(Fmt.hm(start))에 배치했어요", symbol: "calendar.badge.plus") {
            ctx.delete(b)
            DataStore.save(ctx)
        }
        dismiss()
    }
}
