import SwiftUI

struct AssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog = NVIDIAModelCatalog()
    @StateObject private var voicePreview = AssistantSpeech()
    @AppStorage("assistantTranscriber") private var transcriber = "Deepgram"
    @AppStorage("assistantVoiceEngine") private var voiceEngine = "Deepgram"
    @AppStorage("assistantDeepgramVoice") private var deepgramVoice = DeepgramSpeaker.defaultVoice
    @AppStorage("assistantDeepgramEnabled") private var deepgramEnabled = false
    @State private var deepgramKey = ""
    @State private var hasDeepgramKey = AssistantKeychain.read(service: "Deepgram") != nil
    @State private var deepgramMessage: String?
    @AppStorage("assistantModel") private var model = VoiceAssistantService.defaultModel
    @AppStorage("assistantSharingEnabled") private var sharing = false
    @AppStorage("eveningCheckInEnabled") private var eveningCheckInEnabled = true
    @State private var key = ""
    @State private var hasKey = AssistantKeychain.read() != nil
    @State private var connectionPhase: CommitButton.Phase = .idle
    @State private var savePhase: CommitButton.Phase = .idle
    @State private var discoveryTask: Task<Void, Never>?
    @State private var message: String?
    @State private var resultFilter = "Responding"

    private var displayedModels: [NVIDIAAvailableModel] {
        resultFilter == "Responding" ? catalog.models.filter { $0.status == .available } : catalog.models
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    card("Conversation voice") {
                        SecureField(hasDeepgramKey ? "Replace your Deepgram key" : "Paste your Deepgram API key", text: $deepgramKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Save key and enable Deepgram", systemImage: "key.fill") {
                            voicePreview.silence()
                            do {
                                try AssistantKeychain.save(deepgramKey, service: "Deepgram")
                                deepgramKey = ""; hasDeepgramKey = true; deepgramEnabled = true
                                transcriber = "Deepgram"; voiceEngine = "Deepgram"
                                deepgramMessage = "Key saved securely. Preview a voice, then try a conversation to check transcription."
                            } catch { deepgramMessage = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).tint(.purple)
                        Text("Deepgram receives microphone audio while Listening and reply text for speech. Both use your Deepgram account quota. NVIDIA still generates the replies. Keys are stored separately in Keychain.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let deepgramMessage { Text(deepgramMessage).font(.footnote) }
                        SelectMenu("Transcription", selection: $transcriber, options: ["Deepgram", "Apple"],
                            style: SelectMenuStyle(accent: .purple, onAccent: .primary)) {
                                $0 == "Apple" ? "iPhone speech recognition" : "Deepgram · streaming English"
                            }.zIndex(30)
                        SelectMenu("Spoken replies", selection: $voiceEngine, options: ["Deepgram", "Apple"],
                            style: SelectMenuStyle(accent: .purple, onAccent: .primary)) {
                                $0 == "Apple" ? "iPhone voice" : "Deepgram · streaming voice"
                            }.zIndex(20)
                        if voiceEngine == "Deepgram" {
                            SelectMenu("Voice", selection: $deepgramVoice, options: DeepgramSpeaker.voices,
                                style: SelectMenuStyle(accent: .purple, onAccent: .primary)) { DeepgramSpeaker.label($0) }
                                .zIndex(10)
                        }
                        Button(voicePreview.speaking ? "Stop preview" : "Preview selected voice", systemImage: "speaker.wave.2") {
                            if voicePreview.speaking { voicePreview.silence() }
                            else { voicePreview.say("Hi, I'm here. Tell me what you did, and we'll take it one habit at a time.") }
                        }.buttonStyle(.bordered)
                            .disabled(voiceEngine == "Deepgram" && (!hasDeepgramKey || !deepgramEnabled))
                        if let error = voicePreview.error { Text(error).font(.footnote).foregroundStyle(.red) }
                        if hasDeepgramKey {
                            Toggle("Allow audio and speech text to Deepgram", isOn: $deepgramEnabled)
                            Button("Remove Deepgram key", role: .destructive) {
                                voicePreview.silence()
                                AssistantKeychain.remove(service: "Deepgram")
                                hasDeepgramKey = false; deepgramEnabled = false; deepgramKey = ""
                                transcriber = "Apple"; voiceEngine = "Apple"
                                deepgramMessage = "Deepgram key removed. Using iPhone speech."
                            }
                        }
                        Text("Tap the orb once. A short pause sends your turn automatically; listening resumes when playback finishes. Tap the speaking orb to interrupt and talk. End conversation stops the microphone and playback. Habit changes still need confirmation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.zIndex(40)
                    card("NVIDIA connection") {
                        SecureField(hasKey ? "Paste a replacement key" : "Paste your NVIDIA API key", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder).disabled(catalog.checking)
                        Text(hasKey ? "Your key is saved securely on this iPhone." : "Connect your key to find models you can use.")
                            .font(.footnote).foregroundStyle(.secondary)
                        CommitButton(hasKey ? "Find or resume model checks" : "Connect and find models",
                            phase: $connectionPhase, tint: .purple, tintInk: .primary,
                            successTitle: "Models saved", collapses: false) { discover(refresh: false) }
                        Text("This checks NVIDIA's catalog with small chat requests containing no habit data. Checks can use account quota. A full scan may take several minutes.")
                            .font(.caption).foregroundStyle(.secondary)
                        if catalog.checking {
                            ProgressView()
                            Text(catalog.progress).font(.caption).foregroundStyle(.secondary)
                            Button("Stop checking") {
                                discoveryTask?.cancel()
                                connectionPhase = .idle
                            }.buttonStyle(.bordered)
                        } else if hasKey {
                            Button("Refresh list and recheck all models", systemImage: "arrow.clockwise") { discover(refresh: true) }
                                .font(.subheadline)
                        }
                        if let message = message ?? catalog.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    card("Assistant model") {
                        if catalog.usable.isEmpty {
                            Label("Connect your key and finish a model check to choose a model.", systemImage: "sparkles")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            SelectMenu("Choose a responding model", selection: $model, options: catalog.usable,
                                style: SelectMenuStyle(accent: .purple, onAccent: .primary)) { $0 }
                                .zIndex(20)
                            Text("Responding means a small chat request succeeded. It does not guarantee every voice command or structured logging response will succeed.")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("Enable voice assistant", isOn: $sharing)
                            CommitButton("Use selected model", phase: $savePhase, tint: .purple, tintInk: .primary,
                                successTitle: "Connected", collapses: false) {
                                guard !catalog.checking, hasKey, catalog.usable.contains(model) else {
                                    savePhase = .error("Finish checking or stop the scan first."); return
                                }
                                sharing = true
                                savePhase = .success
                            }
                            .disabled(catalog.checking)
                        }
                        if let date = catalog.fetchedAt {
                            Text("Catalog saved \(date.formatted(date: .abbreviated, time: .shortened)). Cached for this key until you refresh or replace it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.zIndex(20)

                    if !catalog.models.isEmpty {
                        card("Model check results") {
                            SelectMenu("Show", selection: $resultFilter, options: ["Responding", "All results"],
                                style: SelectMenuStyle(accent: .purple, onAccent: .primary)) { $0 }
                                .zIndex(10)
                            Text("\(catalog.usable.count) responding · \(catalog.models.count) listed")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(displayedModels) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: item.status == .available ? "checkmark.circle.fill" : "circle.dashed")
                                        .foregroundStyle(item.status == .available ? Color.green : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.id).font(.subheadline).textSelection(.enabled)
                                        Text(item.detail ?? "Not checked yet").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.zIndex(10)
                    }

                    card("Reminders") {
                        ReminderPreferencesView().zIndex(10)
                        Toggle("Evening check-in at 8 pm", isOn: $eveningCheckInEnabled)
                        Button("Allow notifications") { Task { _ = await NotificationManager.shared.requestAuthorization() } }
                            .buttonStyle(.bordered)
                        Text("Reminders follow habit schedules and pause dates. Completing or skipping a habit cancels its remaining alerts today. The queue is renewed whenever you open the app or act on a notification.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    card("Your data") {
                        Text("During a conversation, each completed turn shares your transcript, recent conversation and a habit summary with NVIDIA. Journal notes are excluded; anything you speak is included.")
                        Text("The key stays in Keychain and is excluded from habit backups. The model cache contains model IDs and check results, tied to a one-way fingerprint of the key.")
                        Text("When Deepgram is selected and enabled, microphone audio is streamed to Deepgram and reply text is sent there for speech. Otherwise, iPhone speech recognition uses Apple processing or on-device recognition when supported. Conversation history stays in memory, and logs are saved only after your confirmation.")
                        if hasKey {
                            Button("Remove key and model cache", role: .destructive) {
                                discoveryTask?.cancel()
                                AssistantKeychain.remove()
                                catalog.clear()
                                hasKey = false; sharing = false; model = ""; key = ""
                                connectionPhase = .idle
                            }.disabled(catalog.checking)
                        }
                    }.font(.footnote)
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Voice settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { catalog.load(); selectAvailableModel() }
            .onChange(of: catalog.usable) { _, _ in selectAvailableModel() }
            .onDisappear { discoveryTask?.cancel(); voicePreview.silence() }
            .onChange(of: deepgramVoice) { _, _ in voicePreview.silence() }
            .onChange(of: voiceEngine) { _, _ in voicePreview.silence() }
            .onChange(of: deepgramEnabled) { _, enabled in if !enabled { voicePreview.silence() } }
        }
    }

    private func selectAvailableModel() {
        if !catalog.usable.contains(model), let first = catalog.usable.first { model = first }
    }
    private func discover(refresh: Bool) {
        guard !catalog.checking else { return }
        message = nil
        do {
            if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let changed = key.trimmingCharacters(in: .whitespacesAndNewlines) != AssistantKeychain.read()
                try AssistantKeychain.save(key)
                key = ""
                if changed { catalog.clear(); sharing = false; model = "" }
            }
            hasKey = AssistantKeychain.read() != nil
            guard hasKey else { throw AssistantError.message("Enter your NVIDIA API key first.") }
            catalog.load()
            if refresh { sharing = false }
            connectionPhase = .loading
            discoveryTask = Task { @MainActor in
                do {
                    try await catalog.discover(refresh: refresh)
                    selectAvailableModel()
                    connectionPhase = catalog.usable.isEmpty ? .error("No responding models yet") : .success
                } catch is CancellationError { connectionPhase = .idle }
                catch { message = error.localizedDescription; connectionPhase = .error("Connection check failed") }
            }
        } catch { message = error.localizedDescription; connectionPhase = .error("Check your key") }
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
