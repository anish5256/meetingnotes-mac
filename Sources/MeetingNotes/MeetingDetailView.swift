import SwiftUI
import AppKit

struct MeetingDetailView: View {
    let meeting: Meeting
    @StateObject private var player = MeetingPlayer()
    @State private var tab = "Summary"
    @State private var english = false
    @State private var content = MeetingText()
    @State private var copied = false
    @State private var copyConfirmation: Task<Void, Never>?

    private func eventTime(_ event: MeetingEventContext) -> String {
        func date(_ value: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: value)
        }
        guard let start = date(event.start), let end = date(event.end) else { return event.start + " – " + event.end }
        return start.formatted(date: .abbreviated, time: .shortened) + " – " + end.formatted(date: .omitted, time: .shortened)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(meeting.title).font(.largeTitle).fontWeight(.bold).textSelection(.enabled)
                Text(meeting.subtitle + " · \(meeting.speakers) \(meeting.speakers == 1 ? "speaker" : "speakers")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let event = meeting.event {
                VStack(alignment: .leading, spacing: 4) {
                    Label(event.title, systemImage: "calendar").font(.headline)
                    Text(eventTime(event)).font(.caption).foregroundStyle(.secondary)
                    Text(event.attendees.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }.textSelection(.enabled)
            }
            MeetingPlayerView(player: player)
            HStack {
                Picker("Content", selection: $tab) {
                    Text("Summary").tag("Summary")
                    Text("Transcript").tag("Transcript")
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 260)
                Button {
                    copy(tab == "Summary" ? .summary : .transcript)
                } label: {
                    Label(copied ? "Copied" : "Copy \(tab)", systemImage: "doc.on.doc")
                }
                Spacer()
                if tab == "Transcript" {
                    Toggle("Show English", isOn: $english).toggleStyle(.checkbox)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            if let error = content.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if tab == "Summary" {
                SummaryTextView(source: content.summary)
            } else {
                TranscriptTextView(source: english ? content.english : content.transcript)
            }
        }
        .padding(28)
        .focusedSceneValue(\.meetingCopyActions, MeetingCopyActions(
            transcript: { copy(.transcript) }, summary: { copy(.summary) }))
        .onChange(of: tab) { _, _ in clearConfirmation() }
        .onChange(of: english) { _, _ in clearConfirmation() }
        .task(id: meeting.id) {
            player.load(meeting.folder)
            let folder = meeting.folder
            let loaded = await Task.detached { MeetingText.load(folder) }.value
            guard !Task.isCancelled else { return }
            content = loaded
        }
        .onDisappear { player.stop(); clearConfirmation() }
    }

    private func clearConfirmation() {
        copyConfirmation?.cancel()
        copied = false
    }

    private func copy(_ target: MeetingTextTab) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content.copyText(for: target, showEnglish: english), forType: .string)
        clearConfirmation()
        copied = true
        copyConfirmation = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(1500)) }
            catch { return }
            copied = false
        }
    }

}
