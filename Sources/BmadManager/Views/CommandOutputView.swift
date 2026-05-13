import SwiftUI

struct CommandOutputView: View {
    @EnvironmentObject var runner: CommandRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if runner.isRunning {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Running…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let code = runner.lastExitCode {
                    Text("Exit: \(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(code == 0 ? .green : .red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.output.isEmpty ? "(no output yet)" : runner.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                        .id("output")
                }
                .background(Color.black.opacity(0.05))
                .onChange(of: runner.output) {
                    proxy.scrollTo("output", anchor: .bottom)
                }
            }
        }
    }
}
