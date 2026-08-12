import SwiftUI

struct ProgressStageView: View {
    let progress: RecordingProgress
    var compact: Bool = false

    var body: some View {
        TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(progress.startedAt)))
            if compact {
                compactBody
            } else {
                fullBody(elapsed: elapsed)
            }
        }
    }

    @ViewBuilder
    private var compactBody: some View {
        if case .uploading(let fraction) = progress.stage, fraction > 0 {
            ProgressView(value: fraction)
                .frame(width: 40)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func fullBody(elapsed: Int) -> some View {
        VStack(spacing: 12) {
            if case .uploading(let fraction) = progress.stage, fraction > 0 {
                ProgressView(value: fraction)
                    .frame(width: 200)
                Text("Uploading... \(Int(fraction * 100))%")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text(stageLabel)
                    .foregroundStyle(.secondary)
            }
            Text(elapsedString(elapsed))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var stageLabel: String {
        switch progress.stage {
        case .downloading: return "Downloading from iCloud..."
        case .uploading: return "Uploading..."
        case .waitingForTranscription: return "Transcribing (waiting for OpenAI)..."
        case .summarizing: return "Summarizing..."
        }
    }

    private func elapsedString(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return minutes > 0 ? "\(minutes)m \(secs)s elapsed" : "\(secs)s elapsed"
    }
}
