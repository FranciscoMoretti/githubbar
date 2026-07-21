import AppKit
import GitHubBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @Bindable var updateModel: UpdateModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHubBar")
                        .font(.system(size: 22, weight: .bold))
                    Text("Keep the pull requests that need your attention close at hand.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                SettingsSection(title: "Account", systemImage: "person.crop.circle") {
                    AccountSettingsContent(appModel: appModel)
                }

                SettingsSection(title: "Repositories", systemImage: "folder") {
                    PinnedRepositoriesSettingsView(appModel: appModel)
                }

                SettingsSection(title: "Refresh", systemImage: "arrow.clockwise") {
                    SettingsLabeledRow(title: "Refresh pull requests", detail: "Changes take effect immediately.") {
                        Picker("Refresh cadence", selection: refreshCadenceBinding) {
                            ForEach(RefreshCadence.allCases, id: \.self) { cadence in
                                Text(cadence.displayName).tag(cadence)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 165)
                        .accessibilityLabel("Refresh cadence")
                    }
                }

                SettingsSection(title: "General", systemImage: "gearshape") {
                    SettingsLabeledRow(
                        title: "Launch at login",
                        detail: launchAtLoginDetail
                    ) {
                        Toggle("Launch at login", isOn: launchAtLoginBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(launchAtLoginIsUnavailable)
                            .accessibilityLabel("Launch GitHubBar at login")
                    }
                    if launchAtLoginNeedsSystemSettings {
                        Button("Open Login Items Settings") {
                            openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }

                SettingsSection(title: "Updates", systemImage: "arrow.down.circle") {
                    UpdateSettingsContent(updateModel: updateModel)
                }

                SettingsSection(title: "About", systemImage: "info.circle") {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("GitHubBar \(versionLabel)")
                                .font(.system(size: 11, weight: .semibold))
                            Text("A focused, native pull-request workload for macOS.")
                                .settingsDetail()
                        }
                        Spacer()
                        Link("Project", destination: URL(string: "https://github.com/FranciscoMoretti/GitHubBar")!)
                        Link("Support", destination: URL(string: "https://github.com/FranciscoMoretti/GitHubBar/issues")!)
                    }
                    .controlSize(.small)
                }
            }
            .padding(26)
        }
        .frame(minWidth: 620, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var refreshCadenceBinding: Binding<RefreshCadence> {
        Binding(
            get: { appModel.state.refreshCadence },
            set: { appModel.send(.setRefreshCadence($0)) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appModel.state.launchAtLoginRequested },
            set: { appModel.send(.setLaunchAtLogin($0)) }
        )
    }

    private var launchAtLoginDetail: String {
        switch appModel.state.launchAtLoginStatus {
        case .enabled: "GitHubBar is registered in Login Items."
        case .disabled: "Off by default. Uses the macOS Login Items service."
        case .requiresApproval: "Approval is required in System Settings → Login Items."
        case let .failed(message), let .unavailable(message): message
        }
    }

    private var launchAtLoginIsUnavailable: Bool {
        if case .unavailable = appModel.state.launchAtLoginStatus { return true }
        return false
    }

    private var launchAtLoginNeedsSystemSettings: Bool {
        switch appModel.state.launchAtLoginStatus {
        case .requiresApproval, .failed: true
        case .disabled, .enabled, .unavailable: false
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        return "\(version) (\(build))"
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AccountSettingsContent: View {
    @Bindable var appModel: AppModel

    @ViewBuilder
    var body: some View {
        switch appModel.state.accountConnection {
        case .notChecked, .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub CLI…").settingsDetail()
            }
        case let .connected(login, coverage):
            SettingsLabeledRow(
                title: "@\(login)",
                detail: coverage.isComplete ? "Connected through GitHub CLI." : (coverage.summary ?? "Some repositories may be unavailable.")
            ) {
                HStack(spacing: 8) {
                    Button("Check Again") { appModel.send(.recheckAccountConnection) }
                    Button("Change…") { appModel.send(.requestAccountSelection) }
                }
                .controlSize(.small)
            }
        case let .selectionRequired(candidates):
            Text("Choose the GitHub CLI account this Mac should monitor.")
                .settingsDetail()
            ForEach(candidates) { candidate in
                Button {
                    appModel.send(.confirmAccount(candidate.login))
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("@\(candidate.login)")
                        Spacer()
                        Text(candidate.hostname).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Monitor @\(candidate.login) on \(candidate.hostname)")
            }
        case let .connectionRequired(problem):
            SettingsLabeledRow(
                title: accountProblemTitle(problem),
                detail: "GitHubBar could not verify a usable GitHub CLI account."
            ) {
                Button("Check Again") { appModel.send(.recheckAccountConnection) }
                    .controlSize(.small)
            }
        }
    }

    private func accountProblemTitle(_ problem: AccountConnectionProblem) -> String {
        switch problem {
        case .cliMissing: "GitHub CLI is not installed"
        case .connectionRequired: "GitHub CLI connection required"
        case .incompleteAccess: "GitHub access is incomplete"
        case .unavailable: "GitHub account is unavailable"
        }
    }
}

private struct UpdateSettingsContent: View {
    @Bindable var updateModel: UpdateModel

    var body: some View {
        SettingsLabeledRow(title: title, detail: detail) {
            if updateModel.canCheckForUpdates {
                Button("Check for Updates") { updateModel.checkForUpdates() }
                    .controlSize(.small)
            }
        }
    }

    private var title: String {
        switch updateModel.presentation {
        case .disabled: "Updates unavailable"
        case .ready: "Automatic updates"
        case .checking: "Checking for updates…"
        case .failed: "Update check failed"
        }
    }

    private var detail: String {
        switch updateModel.presentation {
        case let .disabled(message), let .failed(message): message
        case .ready: "GitHubBar checks for signed updates in the background."
        case .checking: "Contacting the update service."
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator.opacity(0.55)) }
    }
}

private struct SettingsLabeledRow<Accessory: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).settingsDetail()
            }
            Spacer(minLength: 10)
            accessory
        }
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    func settingsDetail() -> some View {
        font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
