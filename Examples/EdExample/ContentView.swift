import Ed
import SwiftUI

struct ContentView: View {
    @StateObject private var model = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    Text(model.transcript.isEmpty ? "Load Ed, then ask about the battery or save a note." : model.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("Message Ed", text: $model.input)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(model.isLoaded ? "Loaded" : "Load Ed") {
                        Task { await model.load() }
                    }
                    .disabled(model.isBusy || model.isLoaded)

                    Button("Send") {
                        Task { await model.send() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || !model.isLoaded || model.input.isEmpty)
                }

                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Ed")
            .confirmationDialog(
                "Allow Ed to change app data?",
                isPresented: $model.showApproval,
                titleVisibility: .visible
            ) {
                Button("Allow once") { model.resolveApproval(.allowOnce) }
                Button("Allow for this session") { model.resolveApproval(.allowForSession) }
                Button("Deny", role: .cancel) { model.resolveApproval(.deny) }
            } message: {
                Text(model.approvalSummary)
            }
        }
    }
}
