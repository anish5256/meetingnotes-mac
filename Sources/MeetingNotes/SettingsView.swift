import SwiftUI
import AppKit

struct JobSettings: Sendable {
    let repo: String
    var useDeveloperEngine = false
    let meetings: String
    var summaryProvider: String
    var summaryModel: String
    var correctProvider: String
    var correctModel: String
    let anthropicKey: String
    let proxyURL: String
    let proxyKey: String
    var summaryProviderChosen = false
    var liveCleanupEnabled = true
    var liveCleanupProvider = "claude"
    var liveCleanupModel = "tier:cheap"
    var liveCleanupProviderChosen = false
    var correctProviderChosen = false
}

struct SettingsView: View {
    @ObservedObject var account: ProviderAccount
    @ObservedObject var claudeAccount: ProviderAccount
    @ObservedObject var calendar: CalendarService
    @AppStorage("summaryProvider") private var summaryProvider = "codex"
    @AppStorage("summaryProviderChosen") private var summaryProviderChosen = false
    @AppStorage("correctProviderChosen") private var correctProviderChosen = false
    @AppStorage("summaryModel") private var summaryModel = "tier:default"
    @AppStorage("correctProvider") private var correctProvider = "none"
    @AppStorage("correctModel") private var correctModel = "tier:default"
    @AppStorage("anthropicKey") private var anthropicKey = ""
    @AppStorage("useDeveloperEngine") private var useDeveloperEngine = false
    @AppStorage("repoPath") private var repo = "~/voice-memo-transcriber"
    @AppStorage("meetingsPath") private var meetings = "~/Meetings"
    @AppStorage("proxyURL") private var proxyURL = "http://127.0.0.1:8317/v1"
    @AppStorage("playbackOutputID") private var playbackOutputID = ""
    @AppStorage("proxyKey") private var proxyKey = ""

    @AppStorage("liveCleanupEnabledV2") private var liveCleanupEnabled = true
    @AppStorage("liveCleanupEnabledChosen") private var liveCleanupEnabledChosen = false
    @AppStorage("liveCleanupProviderChosen") private var liveCleanupProviderChosen = false
    @State private var cleanupConfirmation = false
    @State private var cleanupOffPending = false
    @AppStorage("liveCleanupProvider") private var liveCleanupProvider = "claude"
    @AppStorage("liveCleanupModel") private var liveCleanupModel = "tier:cheap"

    var body: some View {
        TabView {
            Form {
                Section {
                    ProviderModelPicker(provider: Binding(get: { correctProvider }, set: { correctProviderChosen = true; correctProvider = $0 }), model: $correctModel, correction: true)
                } header: {
                    Text("Transcript correction")
                } footer: {
                    Text("Optionally correct the transcript before summarizing.")
                }
                Section {
                    ProviderModelPicker(provider: Binding(get: { summaryProvider }, set: { summaryProviderChosen = true; summaryProvider = $0 }), model: $summaryModel, correction: false)
                } header: {
                    Text("Summary")
                } footer: {
                    Text("Settings apply to newly queued jobs.")
                }
                Section {
                    Toggle("Enable live cleanup", isOn: Binding(
                        get: { liveCleanupEnabledChosen ? liveCleanupEnabled : true },
                        set: { updateCleanup($0 ? .turnOn : .requestOff) }))
                    ProviderModelPicker(provider: Binding(get: { cleanupChoice?.provider ?? liveCleanupProvider },
                        set: { liveCleanupProvider = $0; liveCleanupProviderChosen = true }),
                        model: Binding(get: { cleanupChoice?.model ?? liveCleanupModel },
                        set: { value in
                            liveCleanupProvider = cleanupChoice?.provider ?? liveCleanupProvider
                            liveCleanupModel = value
                            liveCleanupProviderChosen = true
                        }),
                                        correction: false, liveCleanup: true)
                    if cleanupChoice == nil {
                        Text("Connect ChatGPT or Claude to use live cleanup")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Live cleanup (while recording)")
                } footer: {
                    Text("On by default. Sends only uncertain lines to a small model (about 1 in 5), roughly 20k tokens per hour, for a much cleaner live transcript.")
                }
            }
            .tabItem { Label("Models", systemImage: "cpu") }

            Form {
                Section {
                    AccountStatusView(account: account)
                    AccountStatusView(account: claudeAccount)
                } header: {
                    Text("Provider accounts")
                } footer: {
                    Text("Connect using your browser to use your ChatGPT or Claude account.")
                }
            }
            .tabItem { Label("Accounts", systemImage: "person.crop.circle") }

            Form {
                Section {
                    HStack {
                        TextField("Meetings folder", text: $meetings)
                        Button("Choose…", action: chooseMeetingsFolder)
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Recordings and processed meetings are saved here.")
                }
                Section {
                    Picker("Playback output", selection: $playbackOutputID) {
                        Text("System Default").tag("")
                        ForEach(AudioDevices.outputs) { device in Text(device.name).tag(device.id) }
                    }
                }
                Section {
                    Text("Transcription engine: " + engineDescription)
                        .textSelection(.enabled)
                    Toggle("Use developer engine", isOn: $useDeveloperEngine)
                    if useDeveloperEngine {
                        TextField("Repository path", text: $repo)
                    }
                } header: {
                    Text("Transcription engine")
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            CalendarSettingsView(calendar: calendar)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            Form {
                Section {
                    TextField("Endpoint URL", text: $proxyURL)
                    if summaryProvider == "proxy" {
                        TextField("Summary model", text: $summaryModel)
                    }
                    if correctProvider == "proxy" {
                        TextField("Correction model", text: $correctModel)
                    }
                    if summaryProvider != "proxy" && correctProvider != "proxy" {
                        TextField("Model", text: .constant("gpt-5")).disabled(true)
                    }
                    SecureField("API key", text: $proxyKey)
                } header: {
                    Text("Custom OpenAI-compatible endpoint")
                } footer: {
                    Text("Choose this provider in Models. Each stage keeps its own model selection.")
                }
                Section {
                    SecureField("Anthropic API key", text: $anthropicKey)
                } header: {
                    Text("Anthropic")
                } footer: {
                    Text("API keys are stored in this Mac’s app preferences.")
                }
            }
            .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .alert("Turn off live cleanup?", isPresented: $cleanupConfirmation) {
            Button("Keep On", role: .cancel) { updateCleanup(.cancel) }
                .keyboardShortcut(.defaultAction)
            Button("Turn Off", role: .destructive) { updateCleanup(.confirmOff) }
        } message: {
            Text("Live cleanup sends only the lines the on-device model is unsure about (about 1 in 5) to a small, fast model: roughly 20k tokens per hour of meeting (less than a cent per hour with an API key). It noticeably improves names, Hinglish spellings and technical words while you record.")
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
    }

    private var cleanupChoice: LiveCleanupConfiguration? {
        ProviderChoice.liveCleanup(provider: liveCleanupProvider, model: liveCleanupModel,
            chosen: liveCleanupProviderChosen, chatGPTConnected: account.state == .connected,
            claudeConnected: claudeAccount.state == .connected,
            anthropicKeySet: !anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func updateCleanup(_ action: LiveCleanupPreference.Action) {
        var state = LiveCleanupPreference(enabled: liveCleanupEnabledChosen ? liveCleanupEnabled : true,
            explicitChoice: liveCleanupEnabledChosen, pendingConfirmation: cleanupOffPending)
        state.apply(action)
        liveCleanupEnabled = state.enabled
        liveCleanupEnabledChosen = state.explicitChoice
        cleanupOffPending = state.pendingConfirmation
        cleanupConfirmation = state.pendingConfirmation
    }

    private var engineDescription: String {
        do {
            return try EngineLocator.resolve(repoPath: repo, useDeveloperEngine: useDeveloperEngine,
                                             resourcesURL: Bundle.main.resourceURL).description
        } catch { return error.localizedDescription }
    }

    private func chooseMeetingsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Paths.url(meetings)
        if panel.runModal() == .OK, let url = panel.url { meetings = url.path }
    }

    static func migrateSettings(defaults d: UserDefaults = .standard) {
        if !d.bool(forKey: "providerSettingsMigrated") {
            if d.object(forKey: "summaryProvider") == nil {
                let provider = d.string(forKey: "backend") ?? "codex"
                d.set(provider, forKey: "summaryProvider")
                let key = provider == "codex" ? "codexModel" :
                    (["claude", "anthropic"].contains(provider) ? "claudeModel" : "proxyModel")
                let fallback = ProviderModelDefaults.model(for: provider, in: .summary)
                if d.object(forKey: "summaryModel") == nil {
                    d.set(d.string(forKey: key) ?? fallback, forKey: "summaryModel")
                }
            }
            d.set(true, forKey: "providerSettingsMigrated")
        }
        for (key, oldDefault) in [("summaryProvider", "codex"), ("correctProvider", "none")] {
            let flag = key + "Chosen"
            if d.object(forKey: flag) == nil {
                d.set(ProviderChoice.migratedChoice(provider: d.string(forKey: key) ?? oldDefault,
                    oldDefault: oldDefault, storedFlag: nil), forKey: flag)
            }
        }
        if !d.bool(forKey: "modelTiersMigrated") {
            for (prefix, fallback, section) in [("summary", "codex", ProviderModelDefaults.Section.summary),
                                               ("correct", "none", .correction),
                                               ("liveCleanup", "claude", .liveCleanup)] {
                let provider = d.string(forKey: prefix + "Provider") ?? fallback
                let saved = d.string(forKey: prefix + "Model") ?? ProviderModelDefaults.model(for: provider, in: section)
                d.set(ProviderModelDefaults.migrated(saved, provider: provider, in: section), forKey: prefix + "Model")
            }
            d.set(true, forKey: "modelTiersMigrated")
        }

    }

    static func applyProviderChoice(chatGPTConnected: Bool, claudeConnected: Bool,
                                    defaults d: UserDefaults = .standard) -> ProviderChoice {
        migrateSettings(defaults: d)
        let previous = d.string(forKey: "summaryProvider") ?? "codex"
        let choice = ProviderChoice(summaryProvider: previous,
            summaryChosen: d.bool(forKey: "summaryProviderChosen"),
            correctProvider: d.string(forKey: "correctProvider") ?? "none",
            correctChosen: d.bool(forKey: "correctProviderChosen"),
            chatGPTConnected: chatGPTConnected, claudeConnected: claudeConnected,
            anthropicKeySet: !(d.string(forKey: "anthropicKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if previous != choice.summaryProvider {
            d.set(ProviderModelDefaults.model(for: choice.summaryProvider, in: .summary), forKey: "summaryModel")
        }
        d.set(choice.summaryProvider, forKey: "summaryProvider")
        if (d.string(forKey: "correctProvider") ?? "none") != choice.correctProvider {
            d.set(ProviderModelDefaults.model(for: choice.correctProvider, in: .correction), forKey: "correctModel")
        }
        d.set(choice.correctProvider, forKey: "correctProvider")
        return choice
    }

    static func snapshot(defaults d: UserDefaults = .standard) -> JobSettings {
        migrateSettings(defaults: d)
        return JobSettings(
            repo: d.string(forKey: "repoPath") ?? "~/voice-memo-transcriber",
            useDeveloperEngine: d.bool(forKey: "useDeveloperEngine"),
            meetings: d.string(forKey: "meetingsPath") ?? "~/Meetings",
            summaryProvider: d.string(forKey: "summaryProvider") ?? "codex",
            summaryModel: d.string(forKey: "summaryModel") ?? "tier:default",
            correctProvider: d.string(forKey: "correctProvider") ?? "none",
            correctModel: d.string(forKey: "correctModel") ?? "tier:default",
            anthropicKey: d.string(forKey: "anthropicKey") ?? "",
            proxyURL: d.string(forKey: "proxyURL") ?? "http://127.0.0.1:8317/v1",
            proxyKey: d.string(forKey: "proxyKey") ?? "",
            summaryProviderChosen: d.bool(forKey: "summaryProviderChosen"),
            liveCleanupEnabled: LiveCleanupPreference.load(defaults: d).enabled,
            liveCleanupProvider: d.string(forKey: "liveCleanupProvider") ?? "claude",
            liveCleanupModel: d.string(forKey: "liveCleanupModel") ?? "tier:cheap",
            liveCleanupProviderChosen: d.bool(forKey: "liveCleanupProviderChosen"),
            correctProviderChosen: d.bool(forKey: "correctProviderChosen"))
    }
}

