import SwiftUI

struct FocusTimerView: View {
    let habitName: String
    @Environment(\.dismiss) private var dismiss
    @State private var seconds = 25 * 60
    @State private var isRunning = false
    @State private var showFinished = false
    private let maximumDuration = 90 * 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("FOCUS SESSION")
                        .font(.caption.weight(.semibold))
                        .tracking(1.3)
                        .foregroundStyle(.secondary)
                    Text(habitName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }

                TimerDial(
                    seconds: $seconds,
                    isRunning: $isRunning,
                    step: 60,
                    maxSeconds: maximumDuration,
                    warningAt: 5 * 60,
                    lineWidth: 15,
                    colors: [.purple, .pink],
                    caption: "FOCUS",
                    style: TimerDial.Style(
                        fill: .purple,
                        track: Color(.systemFill),
                        warning: .orange,
                        finished: .green,
                        knob: .purple,
                        text: .primary,
                        secondaryText: .secondary,
                        showsTicks: true,
                        digitSize: 50,
                        showsControls: true
                    ),
                    onFinish: { showFinished = true }
                )
                .frame(height: 320)
                .accessibilityLabel("Focus countdown timer")

                Button {
                    seconds = min(seconds + 60, maximumDuration)
                } label: {
                    Label("Add 1 minute", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                .disabled(isRunning || seconds >= maximumDuration)

                Text("The timer is not saved as a habit completion automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Focus timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Focus session complete", isPresented: $showFinished) {
                Button("Done", role: .cancel) { }
            } message: {
                Text("Nice work. Your habit was not marked complete.")
            }
        }
    }
}
