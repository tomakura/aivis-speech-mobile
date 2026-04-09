import SwiftUI
import AivisMobileCore

public struct AivisSpeechRootView: View {
    @StateObject private var viewModel: AppViewModel

    public init(
        runtimeStatus: EngineRuntimeStatus? = nil,
        modelRepository: (any ModelRepository)? = nil,
        supportedDevices: SupportedDevices? = nil,
        installedModels: [InstalledModel]? = nil,
        speechEngine: (any SpeechEngine)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: AppViewModel.bootstrap(
                runtimeStatus: runtimeStatus ?? .previewRoot,
                modelRepository: modelRepository,
                supportedDevices: supportedDevices,
                installedModels: installedModels,
                speechEngine: speechEngine
            )
        )
    }

    public var body: some View {
        RootView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension EngineRuntimeStatus {
    static let previewRoot = EngineRuntimeStatus(
        providerName: "プレビューランタイム",
        availability: .unavailable,
        preferredExecutionProvider: "Core ML 準備中",
        linkedVersion: nil,
        coreMLAvailable: true,
        notes: ["ランタイムはまだ注入されていません"]
    )
}
