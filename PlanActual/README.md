# 계획과 실제 (PlanActual) — iOS 앱

‘Plan & Actual 클론 · iOS 최종 디자인 기획’ 캔버스(화면 01–19, 핸드오프 H1–H4)를 바탕으로 만든 SwiftUI 앱이에요.
계획 트랙과 실제 트랙을 나란히 두고, 카테고리 기준으로 일치율을 계산하고, 어긋난 곳에만 주황을 써요.

- iOS 18 이상 · SwiftUI · iPhone 세로 전용
- 저장: SwiftData + CloudKit(개인 iCloud DB) · App Group 공유 컨테이너
- 연동: EventKit(캘린더 · 미리알림), HealthKit(수면 · 운동 읽기), UserNotifications(액션 3개), ActivityKit(라이브 액티비티), WidgetKit

## 열고 실행하기

1. **Xcode 16 이상**에서 `PlanActual/PlanActual.xcodeproj`를 열어요. (폴더 동기화 그룹을 쓰는 형식이라 Xcode 15에서는 열리지 않아요.)
2. 프로젝트 ▸ **Build Settings**(PROJECT 수준)에서 아래 세 값을 내 것으로 바꿔요. 앱 · 위젯 확장 · 엔타이틀먼트가 모두 이 값을 따라가요.
   | 설정 | 기본값 |
   | --- | --- |
   | `APP_BUNDLE_ID` | `com.example.planactual` (위젯은 자동으로 `.widgets`가 붙어요) |
   | `APP_GROUP_ID` | `group.com.example.planactual` |
   | `ICLOUD_CONTAINER_ID` | `iCloud.com.example.planactual` |
3. 두 타깃(`PlanActual`, `PlanActualWidgetsExtension`)의 **Signing & Capabilities**에서 Team을 고르면 App Group · iCloud(CloudKit) · Push · HealthKit 기능이 등록돼요.
4. 실기기에서 실행해요. 햅틱, 시트 플릭, 라이브 액티비티는 시뮬레이터로 판단하지 마세요(H2 ‘출시 전 확인’).

> **무료(개인) 개발자 계정**이면 iCloud · Push · HealthKit을 서명할 수 없어요. `Config/PlanActual.entitlements`에서 해당 키를 지우면 빌드돼요.
> 앱은 iCloud 저장소를 열지 못하면 자동으로 기기 안 저장소로 바꿔서 동작해요.

> 이 코드는 Xcode가 없는 Linux 환경에서 작성했어요. Swift 문법 파서로는 모든 파일을 확인했지만 실제 컴파일러로 빌드하지는 못했어요.
> 첫 빌드에서 타입 추론이나 API 시그니처 때문에 작은 오류가 날 수 있어요. 오류 메시지를 알려주시면 바로 고칠게요.

## 화면 ↔ 파일

| 캔버스 | 화면 | 파일 |
| --- | --- | --- |
| 01 | 오늘 · 두 트랙(계획/실제 · 싱크 솔기 · 현재 시각 · 타이머 막대 · 토스트+실행 취소) | `UI/Today/TodayView.swift` |
| 01 내부 | “했나요?” 확인 시트 | `UI/Today/ConfirmSheet.swift` |
| 02 | 계획 짜기 · 길게 눌러 끌기 / 눌러서 1시간 · 15분 스냅 · 핸들 | `UI/Plan/PlanView.swift`, `PlanEditorSheet.swift` |
| 03 | 끝난 계획 알림(했어요/일부만/안 했어요) · 라이브 액티비티 · 다이내믹 아일랜드 · 홈/잠금 위젯 | `Services/NotificationService.swift`, `PlanActualWidgets/*`, `Shared/TimerActivity.swift` |
| 04 | 하루 마감(전체 화면) | `UI/Close/DayCloseFlow.swift` |
| 05 | 목표 & 할 일 | `UI/Goals/GoalsView.swift` |
| 06 | 주간 시간표 보기 | `UI/Today/WeekScreen.swift` |
| 07 | 시간표 여러 개 · 템플릿 | `UI/Settings/TimetablesView.swift` |
| 08 | 반복 일정 → 시간표 | `UI/Settings/TimetableConvertSheet.swift` |
| 09 | 카테고리 › 세부내역 · 밀어서 보관/삭제 | `UI/Settings/CategoriesView.swift` |
| 10 | 세부내역 삭제 · 기록 처리 · 길게 눌러 삭제 | `UI/Settings/CategoriesView.swift` (`DeleteConfirmSheet`) |
| 11 | 보관함 | `UI/Settings/CategoriesView.swift` (`ArchiveView`) |
| 12 | 캘린더 연동 · 캘린더별 지정 | `UI/Settings/CalendarSyncView.swift` |
| 13 | 캘린더 일정 편집 · 삭제(이 일정만/이후 모두) | `UI/Settings/CalendarSyncView.swift` (`EventEditSheet`) |
| 14 | 할 일 · 미리알림 연동 | `UI/Goals/TodosView.swift` |
| 15 | 남은 하루 다시 맞추기(뒤로 밀기/내일로/줄여서 넣기) | `UI/Today/ReplanSheet.swift` |
| 16 | 주간 어긋남 인사이트(Swift Charts 히트맵) | `UI/Insights/InsightsView.swift` |
| 17 | 빈 시간 채우기 | `UI/Close/GapFillView.swift` |
| 18 | 설정 · 하루 범위(휠 2개) · iCloud | `UI/Settings/SettingsView.swift` |
| 19 | 카테고리 색 · 테마 4종 · HEX · 라이트/다크 미리보기 · 대비 | `UI/Settings/ColorPickerSheet.swift` |

## 규칙이 사는 곳 (H4)

- **일치율 · 카테고리 기준**, 싱크 솔기, 밀린 시간, 빈 시간: `Core/MatchEngine.swift` — 하루 범위를 분 단위로 펼쳐 계산
- **계획 레이어 우선순위**(캘린더 > 직접 계획 > 시간표), 겹침 레인, 시간표는 그릴 때 계산: `Core/PlanResolver.swift`
- **하루 범위**(기본 06:00 – 다음 날 02:00, 지난 날은 DaySummary 스냅샷): `Core/DayMath.swift`
- **사용자 색 파생 계산**(틴트 12% · 계획 글자 38% · 다크 솔리드 28% · 대비 높은 글자색 · 주황/빨강 경고): `Shared/HexColor.swift`
- **확인 · 타이머(한 번에 하나, 다른 기기 기록 이어받기) · 보관/삭제 · 하루 마감 스냅샷 · 기기 간 중복 정리**: `Core/DataStore.swift`
- **모델**(CloudKit 제약: 기본값 · 옵셔널 관계 · unique 없음): `Models/Models.swift`

## 구조

```
PlanActual/
├─ PlanActual.xcodeproj
├─ PlanActual/            앱 타깃
│  ├─ App/                진입점 · 라우터 · 토스트 · 저장소 생성
│  ├─ Models/             SwiftData 모델
│  ├─ Core/               날짜 · 계획 합치기 · 일치율 · 데이터 작업
│  ├─ Services/           캘린더/미리알림 · 알림 · 라이브 액티비티 · 건강 · 동기화 상태 · 위젯 · CSV
│  └─ UI/                 탭별 화면과 공통 컴포넌트
├─ PlanActualWidgets/     위젯 확장 (홈 S · 잠금 원형 · 라이브 액티비티)
├─ Shared/                앱과 위젯이 함께 쓰는 코드 · 컬러 에셋(라이트/다크)
└─ Config/                Info.plist · 엔타이틀먼트
```
