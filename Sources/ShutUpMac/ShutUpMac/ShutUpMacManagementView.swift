import Dispatch
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
    let requestDatabaseStatistics:
        (
            @escaping @MainActor @Sendable (
                DatabaseStatisticsResult
            ) -> Void
        ) -> Void

    let replaceNotilogRedactionPolicy:
        (RedactionPolicy) -> Void

    private var selectedTabBinding:
        Binding<ShutUpMacTab>
    {
        let navigation = navigation

        return Binding(
            get: {
                navigation.selectedTab
            },
            set: { selectedTab in
                guard navigation.selectedTab
                    != selectedTab
                else {
                    return
                }

                DispatchQueue.main.async {
                    navigation.selectedTab =
                        selectedTab
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selectedTabBinding) {
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
                store: activityStore,
                createRuleFromNotification: { seed in
                    navigation.beginRuleCreation(
                        from: seed
                    )
                }
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
                navigation: navigation,
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

            AdvancedView(
                requestDatabaseStatistics:
                    requestDatabaseStatistics
            )
                .tabItem {
                    Label(
                        ShutUpMacTab.advanced.title,
                        systemImage:
                            ShutUpMacTab.advanced.systemImage
                    )
                }
                .tag(ShutUpMacTab.advanced)
        }
        .frame(
            minWidth: 960,
            minHeight: 640
        )
    }
}
