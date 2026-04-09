import SwiftUI
import AivisMobileCore
import AivisSpeechiOS
import AivisSpeechRuntime

@main
struct AivisSpeechApp: App {
    var body: some Scene {
        WindowGroup {
            RuntimeBootView()
        }
    }
}

private struct RuntimeBootView: View {
    @State private var bootstrapResult: RuntimeBootstrapResult?
    @State private var bootstrapError: String?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                if let bootstrapResult {
                    AivisSpeechRootView(
                        runtimeStatus: bootstrapResult.snapshot.runtimeStatus,
                        modelRepository: bootstrapResult.repository,
                        supportedDevices: bootstrapResult.snapshot.supportedDevices,
                        installedModels: bootstrapResult.snapshot.installedModels,
                        speechEngine: bootstrapResult.speechEngine
                    )
                } else {
                    VStack(spacing: 18) {
                        ProgressView()
                            .controlSize(.large)
                        Text("ランタイムを初期化しています")
                            .font(.headline)
                        if let bootstrapError {
                            Text(bootstrapError)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(24)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task {
            guard bootstrapResult == nil else { return }
            do {
                bootstrapResult = try await RuntimeBootstrap.bootstrapDefault()
            } catch {
                bootstrapError = error.localizedDescription
                let recoveryRepository = ORTModelRepository(
                    baseRepository: FileModelRepository(
                        rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("AivisSpeechMobileRecovery", isDirectory: true)
                    )
                )
                bootstrapResult = RuntimeBootstrapResult(
                    repository: recoveryRepository,
                    snapshot: RuntimeLaunchSnapshot(
                        runtimeStatus: ONNXRuntimeSupport.statusSnapshot(),
                        supportedDevices: ONNXRuntimeSupport.supportedDevices(),
                        installedModels: []
                    ),
                    speechEngine: StyleBertVITS2SpeechEngine(modelRepository: recoveryRepository)
                )
            }
        }
    }
}
