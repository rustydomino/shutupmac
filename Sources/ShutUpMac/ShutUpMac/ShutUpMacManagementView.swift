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

    let initialRetentionConfiguration:
        RetentionConfiguration

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

    let resetActivityDatabase:
        (
            @escaping @MainActor @Sendable (
                ActivityDatabaseResetResult
            ) -> Void
        ) -> Void

    let updateRetentionLimits:
        (
            Int,
            Int,
            @escaping @MainActor @Sendable (
                RetentionLimitsUpdateResult
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
            .navigationTitle("ShutUpMac Settings")
            .tag(ShutUpMacTab.general)

            HotKeySettingsView()
                .tabItem {
                    Label(
                        ShutUpMacTab.hotKeys.title,
                        systemImage:
                        ShutUpMacTab.hotKeys.systemImage
                )
            }
            .navigationTitle("ShutUpMac Settings")
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
            .navigationTitle("ShutUpMac Settings")
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
            .navigationTitle("ShutUpMac Settings")
            .tag(ShutUpMacTab.rules)

            AdvancedView(
                initialRetentionConfiguration:
                    initialRetentionConfiguration,
                requestDatabaseStatistics:
                    requestDatabaseStatistics,
                resetActivityDatabase:
                    resetActivityDatabase,
                updateRetentionLimits:
                    updateRetentionLimits
            )
            .tabItem {
                Label(
                    ShutUpMacTab.advanced.title,
                    systemImage:
                    ShutUpMacTab.advanced.systemImage
                )
            }
            .navigationTitle("ShutUpMac Settings")
            .tag(ShutUpMacTab.advanced)
        }
        .frame(
            minWidth: 860,
            minHeight: 520
        )
    }
}
