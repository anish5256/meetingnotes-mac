import SwiftUI

struct ProviderModelPicker: View {
    @Binding var provider: String
    @Binding var model: String
    let correction: Bool
    var liveCleanup = false
    @State private var custom = false

    private var claude: Bool { ["claude", "anthropic"].contains(provider) }
    private var models: [String] {
        claude ? ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"] : (provider == "codex" ? ["", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-6-astra"] : [""])
    }
    private var section: ProviderModelDefaults.Section {
        liveCleanup ? .liveCleanup : (correction ? .correction : .summary)
    }
    private func label(for model: String) -> String {
        switch model {
        case "": return provider == "codex" ? "Default (Codex chooses)" : "Default"
        case "gpt-6.1-sol": return "GPT-6.1-Sol"
        case "gpt-6.1-terra": return "GPT-6.1 Terra"
        case "gpt-6-luna": return "GPT-6-Luna — fast & cheap"
        case "gpt-6-astra": return "GPT-6-Astra — most capable"
        case "claude-haiku-5-5": return "claude-haiku-5-5 — fast & cheap"
        default: return model
        }
    }
    private var selection: Binding<String> {
        Binding(get: { custom || !models.contains(model) ? "custom" : model }, set: {
            custom = $0 == "custom"
            if !custom { model = $0 }
        })
    }

    var body: some View {
        Picker("Provider", selection: Binding(get: { provider }, set: { value in
            let previous = provider
            model = ProviderModelDefaults.model(model, changingFrom: previous, to: value, in: section)
            provider = value
            if previous != value { custom = false }
        })) {
            if correction { Text("Off").tag("none") }
            Text("ChatGPT (your account)").tag("codex")
            Text("Claude (your account)").tag("claude")
            Text("Claude API key").tag("anthropic")
            if !liveCleanup {
                Text("Custom OpenAI-compatible endpoint").tag("proxy")
                if !correction { Text("Offline test").tag("fake") }
            }
        }
        if provider == "proxy" {
            TextField("Model", text: $model)
        } else if provider != "none" {
            Picker("Model", selection: selection) {
                ForEach(models, id: \.self) { value in
                    Text(label(for: value)).tag(value)
                }
                Text("Custom…").tag("custom")
            }
            if selection.wrappedValue == "custom" {
                TextField("Custom model", text: $model)
            }
        }
    }
}

struct AccountStatusView: View {
    @ObservedObject var account: ProviderAccount

    private var busy: Bool { account.state == .checking || account.state == .connecting }
    private var status: String {
        switch account.state {
        case .checking: return "Checking…"
        case .connected: return "Connected"
        case .connecting: return "Finish signing in in your browser…"
        case .missing: return account.provider.missingMessage
        case .notConnected: return "Not connected"
        case .failed(let message): return message
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(account.state == .connected ? Color.green : Color.secondary)
                .frame(width: 7, height: 7).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.provider.name)
                Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            if account.state == .connected {
                Button("Sign Out") { Task { await account.disconnect() } }
            } else {
                Button("Connect") { Task { await account.connect() } }.disabled(busy || account.state == .missing)
            }
        }.padding(.vertical, 4)
    }
}
