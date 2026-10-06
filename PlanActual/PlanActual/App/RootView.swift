import SwiftUI

/// 5개 탭 · 탭마다 NavigationStack. 탭 전환은 애니메이션 없이 즉시.
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("오늘", systemImage: "rectangle.split.2x1", value: AppTab.today) {
                TodayView()
            }
            Tab("계획", systemImage: "calendar.badge.plus", value: AppTab.plan) {
                PlanView()
            }
            Tab("목표", systemImage: "target", value: AppTab.goals) {
                GoalsView()
            }
            Tab("인사이트", systemImage: "chart.bar", value: AppTab.insights) {
                InsightsView()
            }
            Tab("설정", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(Palette.ink)
    }
}
