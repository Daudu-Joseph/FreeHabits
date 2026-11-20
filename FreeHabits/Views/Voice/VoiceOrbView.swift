import SwiftUI
import SwiftData

struct VoiceOrbView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]
    @StateObject private var speech = AssistantSpeech()
    @AppStorage("assistantModel") private var model = VoiceAssistantService.defaultModel
    @AppStorage("assistantSharingEnabled") private var sharing = false
    @State private var showSettings = false
    @State private var thinking = false
    @State private var reply = "Tap the orb and tell me what you did."
    @State private var pending: [PreparedHabitLog] = []
    @State private var history: [AssistantMessage] = []
    @State private var requestTask: Task<Void, Never>?
    @State private var microphoneTask: Task<Void, Never>?
    @State private var error: String?

    private var activeHabits: [Habit] { habits.filter { !$0.isArchived } }
    private var status: String {
        if speech.requesting { return "Getting ready" }
        if speech.listening { return "Listening" }
        if thinking { return "Thinking" }
        if speech.speaking { return "Speaking" }
        if !pending.isEmpty { return "Review your check-in" }
        return "Ready when you are"
    }
    private var palette: AssistantOrb.Palette {
        if speech.listening {
            return .init(bands: [0x16E0BD, 0x54CBFF, 0x663AFF, 0xBA6BFF], ground: 0x090F26,
                         rimCool: 0x68E9FF, rimWarm: 0xC78CFF)
        }
        if !pending.isEmpty {
            return .init(bands: [0x39D98A, 0x6FE6C0, 0x4C9AFF, 0x8757FF], ground: 0x081F20,
                         rimCool: 0x5FE8C1, rimWarm: 0x9B79FF)
        }
        return .siri
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(status.uppercased())
                        .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        .padding(.top, 20)

                    Button(action: tapOrb) {
                        ZStack {
                            Circle().fill(.clear)
                            AssistantOrb(size: 280, palette: palette).accessibilityHidden(true)
                        }
                        .frame(width: 280, height: 280)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(thinking || speech.requesting)
                    .accessibilityLabel(speech.listening ? "Stop listening" : "Talk to FreeHabits")
                    .accessibilityValue(status)
                    .accessibilityHint("Tap to start or stop the microphone. Review the transcript before sending.")

                    if speech.listening || !speech.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("You said", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("Your voice note", text: $speech.transcript, axis: .vertical)
                                .lineLimit(2...5)
                                .disabled(speech.listening || thinking)
                            if speech.listening {
                                Button("Finish recording", systemImage: "stop.circle.fill") { speech.stop() }
                            } else if pending.isEmpty {
                                Button("Send voice note", systemImage: "arrow.up.circle.fill", action: send)
                                    .buttonStyle(.borderedProminent).tint(.purple)
                                    .disabled(thinking || speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    }

                    Text(reply).font(.title3.weight(.medium)).multilineTextAlignment(.center)

                    if !pending.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Ready to log").font(.headline)
                            ForEach(pending) { log in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(log.habit.name, systemImage: log.habit.icon).font(.subheadline.bold())
                                    Text(log.summary).font(.subheadline)
                                    Text(log.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let note = log.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            HStack {
                                Button("Cancel", role: .cancel) {
                                    pending = []
                                    reply = "Nothing saved. Tap the orb to try again."
                                    speech.transcript = ""
                                    speech.silence()
                                }.buttonStyle(.bordered)
                                Spacer()
                                Button("Save logs", systemImage: "checkmark", action: save)
                                    .buttonStyle(.borderedProminent).tint(.purple)
                            }
                        }.padding(20)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    }

                    if speech.speaking {
                        Button("Stop speaking", systemImage: "speaker.slash") { speech.silence() }
                            .buttonStyle(.bordered)
                    }
                    if let message = error ?? speech.error {
                        Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    if !sharing || AssistantKeychain.read() == nil {
                        Button("Connect NVIDIA", systemImage: "key.fill") { showSettings = true }
                            .buttonStyle(.borderedProminent).tint(.purple)
                    }
                    Text("Try “I drank two glasses of water” or “How am I doing this week?”")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("The microphone runs only while Listening. Tap Send to share your words and habit summary with NVIDIA.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Voice")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Voice settings", systemImage: "slider.horizontal.3") { showSettings = true }
                    .labelStyle(.iconOnly)
            } }
            .sheet(isPresented: $showSettings) { AssistantSettingsView() }
            .onChange(of: showSettings) { _, showing in if showing { stopSession() } }
            .onDisappear(perform: stopSession)
            .onChange(of: scenePhase) { _, phase in if phase != .active { stopSession() } }
        }
    }

    private func tapOrb() {
        guard pending.isEmpty else { speech.say("Review your check-in, then tap Save logs or Cancel."); return }
        guard sharing, AssistantKeychain.read() != nil else { showSettings = true; return }
        if speech.listening { speech.stop() }
        else {
            error = nil
            microphoneTask = Task { await speech.start() }
        }
    }

    private func send() {
        guard !thinking, sharing, pending.isEmpty else { return }
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4000 else { error = "Keep your voice note under 4,000 characters."; return }
        speech.stop()
        speech.silence()
        error = nil
        thinking = true
        let snapshot = activeHabits
        requestTask = Task { @MainActor in
            defer { thinking = false }
            do {
                let answer = try await VoiceAssistantService.answer(text, habits: snapshot, model: model, history: history)
                try Task.checkCancellation()
                pending = try VoiceAssistantService.prepare(answer.logs, habits: snapshot)
                reply = answer.reply
                if !pending.isEmpty { reply += " Tap Save logs to confirm." }
                history += [.init(role: "user", content: text), .init(role: "assistant", content: answer.reply)]
                history = Array(history.suffix(6))
                speech.transcript = ""
                speech.say(reply)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        do {
            try VoiceAssistantService.save(pending, container: context.container)
            pending = []
            reply = "Saved your check-in."
            history.append(.init(role: "user", content: "I confirmed and saved those proposed logs."))
            speech.say(reply)
        } catch { self.error = error.localizedDescription }
    }

    private func stopSession() {
        microphoneTask?.cancel()
        requestTask?.cancel()
        speech.stop()
        speech.silence()
    }
}

