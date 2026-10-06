import SwiftData
import SwiftUI

/// 카테고리 › 세부내역 고르기 (계획 추가, 다른 걸 했어요, 캘린더 지정 등)
struct DetailPicker: View {
    @Binding var selection: ActivityDetail?
    var allowsCreate = true
    @Query(sort: \ActivityCategory.sortOrder) private var categories: [ActivityCategory]
    @Environment(\.modelContext) private var ctx
    @State private var categoryID: UUID?
    @State private var newName = ""
    @State private var showingNew = false

    private var visibleCategories: [ActivityCategory] { categories.filter { $0.archivedAt == nil } }
    private var currentCategory: ActivityCategory? {
        visibleCategories.first { $0.id == (categoryID ?? selection?.category?.id) } ?? visibleCategories.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "카테고리")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleCategories) { c in
                            CategoryChip(name: c.name, hex: c.colorHex, selected: c.id == currentCategory?.id) {
                                categoryID = c.id
                                if selection?.category?.id != c.id { selection = c.activeDetails.first }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
            if let cat = currentCategory {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "세부내역 · \(cat.name)")
                    FlowLayout(spacing: 8) {
                        ForEach(cat.activeDetails) { d in
                            DetailChip(name: d.name, hex: cat.colorHex, selected: selection?.id == d.id) {
                                selection = d
                            }
                        }
                        if allowsCreate {
                            OutlineChip(title: "세부내역", symbol: "plus") { showingNew = true }
                        }
                    }
                }
            }
        }
        .onAppear {
            if categoryID == nil { categoryID = selection?.category?.id ?? visibleCategories.first?.id }
        }
        .alert("새 세부내역", isPresented: $showingNew) {
            TextField("이름", text: $newName)
            Button("취소", role: .cancel) { newName = "" }
            Button("추가") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let cat = currentCategory else { return }
                selection = DataStore.makeDetail(name: name, in: cat, ctx: ctx)
                DataStore.save(ctx)
                newName = ""
            }
        } message: {
            Text("\(currentCategory?.name ?? "") 안에 만들어요.")
        }
    }
}

/// 세부내역 하나를 골라 바로 닫는 시트
struct DetailPickerSheet: View {
    let title: String
    var message: String? = nil
    let confirmTitle: String
    var initial: ActivityDetail? = nil
    let onPick: (ActivityDetail) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ActivityDetail?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(Palette.inkSecondary)
                    }
                    DetailPicker(selection: $selection)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(confirmTitle) {
                    if let s = selection { onPick(s); dismiss() }
                }
                .buttonStyle(.primary)
                .disabled(selection == nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(Palette.surface)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
        }
        .onAppear { if selection == nil { selection = initial } }
        .appSheet()
    }
}
