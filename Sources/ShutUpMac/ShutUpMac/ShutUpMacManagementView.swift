import NotilogCore
import SwiftUI

struct ShutUpMacManagementView: View {
    @ObservedObject
    var navigation: ShutUpMacNavigation

    @ObservedObject
    var activityStore: ActivityStore

    @ObservedObject
    var automationConfigurationStore:
        AutomationConfigurationStore

    let saveAutomationConfiguration:
        (AutomationConfig) -> Void

    let setNotilogDatabaseLoggingEnabled:
        (
            Bool,
            @escaping @MainActor @Sendable (
                DatabaseLoggingUpdateResult
            ) -> Void
        ) -> Void

    let setNotilogRulesAutoDismissEnabled:
        (Bool) -> Void

    let replaceNotilogRedactionPolicy:
        (RedactionPolicy) -> Void

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            SettingsView(
               setNotilogDatabaseLoggingEnabled:
                    setNotilogDatabaseLoggingEnabled,
                replaceNotilogRedactionPolicy:
                    replaceNotilogRedactionPolicy
            )
            .tabItem {
                Label(
                    ShutUpMacTab.general.title,
                    systemImage:
                        ShutUpMacTab.general.systemImage
                )
            }
            .tag(ShutUpMacTab.general)

            HotKeySettingsView()
            .tabItem {
                Label(
                    ShutUpMacTab.hotKeys.title,
                    systemImage:
                        ShutUpMacTab.hotKeys.systemImage
                )
            }
            .tag(ShutUpMacTab.hotKeys)

            ActivityView(
                store: activityStore
            )
            .tabItem {
                Label(
                    ShutUpMacTab.activity.title,
                    systemImage:
                        ShutUpMacTab.activity.systemImage
                )
            }
            .tag(ShutUpMacTab.activity)

            RulesView(
                store: automationConfigurationStore,
                saveAutomationConfiguration:
                    saveAutomationConfiguration,
                setNotilogRulesAutoDismissEnabled:
                    setNotilogRulesAutoDismissEnabled
            )
            .tabItem {
                Label(
                    ShutUpMacTab.rules.title,
                    systemImage:
                        ShutUpMacTab.rules.systemImage
                )
            }
           .tag(ShutUpMacTab.rules)
        }
        .frame(
            minWidth: 960,
            minHeight: 640
        )
    }
}
