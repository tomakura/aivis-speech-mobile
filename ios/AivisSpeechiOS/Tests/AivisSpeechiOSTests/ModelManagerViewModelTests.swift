import Foundation
import Testing
@testable import AivisSpeechiOS
import AivisMobileCore

struct ModelManagerViewModelTests {
    @Test
    @MainActor
    func activateLoadsInspectionAndMarksModelActive() async {
        let modelID = UUID(uuidString: "4c9ca6f3-7d9f-4093-a8dd-f87f0d7c2724") ?? UUID()
        let repository = MockInspectableRepository(initialModels: [
            InstalledModel(
                id: modelID,
                name: "Sample Voice Model",
                version: "1.0.0",
                loadState: .installed
            )
        ])

        let viewModel = ModelManagerViewModel(
            installedModels: await repository.models(),
            supportedDevices: SupportedDevices(cpu: true, gpu: false, neuralEnginePreferred: true, coreML: true),
            modelRepository: repository,
            runtimeStatus: EngineRuntimeStatus(
                providerName: "ONNX Runtime Mobile",
                availability: .linked,
                preferredExecutionProvider: "CoreML Execution Provider",
                linkedVersion: "1.24.2",
                coreMLAvailable: true
            )
        )

        await viewModel.activateModel(modelID)

        #expect(viewModel.activeModel?.id == modelID)
        #expect(viewModel.inspectionByModelID[modelID]?.inputNames == ["input_ids", "style_vector"])
        #expect(viewModel.busyModelID == nil)
    }

    @Test
    @MainActor
    func unloadClearsInspectionAndResetsState() async {
        let modelID = UUID(uuidString: "6ad4f1d8-024a-4dc7-b0d8-24bce9822489") ?? UUID()
        let repository = MockInspectableRepository(initialModels: [
            InstalledModel(
                id: modelID,
                name: "Misty Narrator",
                version: "0.9.2",
                loadState: .loaded
            )
        ])

        let viewModel = ModelManagerViewModel(
            installedModels: await repository.models(),
            supportedDevices: SupportedDevices(),
            modelRepository: repository,
            runtimeStatus: EngineRuntimeStatus(
                providerName: "ONNX Runtime Mobile",
                availability: .linked,
                preferredExecutionProvider: "CPU fallback",
                linkedVersion: "1.24.2",
                coreMLAvailable: false
            )
        )

        await viewModel.loadModel(modelID)
        #expect(viewModel.inspectionByModelID[modelID] != nil)

        await viewModel.unloadModel(modelID)

        #expect(viewModel.installedModels.first?.loadState == .installed)
        #expect(viewModel.inspectionByModelID[modelID] == nil)
        #expect(viewModel.busyModelID == nil)
    }

    @Test
    @MainActor
    func importModelRefreshesInstalledModels() async {
        let repository = MockInspectableRepository(initialModels: [])
        let viewModel = ModelManagerViewModel(
            installedModels: [],
            supportedDevices: SupportedDevices(),
            modelRepository: repository,
            runtimeStatus: EngineRuntimeStatus(
                providerName: "ONNX Runtime Mobile",
                availability: .linked,
                preferredExecutionProvider: "CoreML Execution Provider",
                linkedVersion: "1.24.2",
                coreMLAvailable: true
            )
        )

        await viewModel.importModel(from: URL(fileURLWithPath: "/tmp/imported.onnx"))

        #expect(viewModel.installedModels.count == 1)
        #expect(viewModel.installedModels.first?.name == "imported")
        #expect(viewModel.statusMessage == "imported.onnx を読み込みました。")
    }
}

private actor MockInspectableRepository: InspectableModelRepository {
    private var storedModels: [InstalledModel]

    init(initialModels: [InstalledModel]) {
        self.storedModels = initialModels
    }

    func models() -> [InstalledModel] {
        storedModels
    }

    func installedModels() async throws -> [InstalledModel] {
        storedModels
    }

    func installModel(fromFile fileURL: URL) async throws -> InstalledModel {
        let imported = InstalledModel(
            id: UUID(),
            name: fileURL.deletingPathExtension().lastPathComponent,
            version: "imported",
            sourceURL: fileURL,
            loadState: .installed,
            localFileURL: fileURL
        )
        storedModels.append(imported)
        return imported
    }

    func installModel(fromRemote remoteURL: URL) async throws -> InstalledModel {
        throw MockError.unsupported
    }

    func updateModel(id: UUID) async throws -> InstalledModel {
        throw MockError.unsupported
    }

    func loadModel(id: UUID) async throws {
        storedModels = storedModels.map { model in
            var mutableModel = model
            if model.id == id {
                mutableModel.loadState = .loaded
            }
            return mutableModel
        }
    }

    func activateModel(id: UUID) async throws {
        storedModels = storedModels.map { model in
            var mutableModel = model
            if model.id == id {
                mutableModel.loadState = .active
            } else if model.loadState == .active {
                mutableModel.loadState = .loaded
            }
            return mutableModel
        }
    }

    func unloadModel(id: UUID) async throws {
        storedModels = storedModels.map { model in
            var mutableModel = model
            if model.id == id {
                mutableModel.loadState = .installed
            }
            return mutableModel
        }
    }

    func removeModel(id: UUID) async throws {
        storedModels.removeAll { $0.id == id }
    }

    func inspection(for id: UUID) async throws -> ModelInspectionSummary {
        guard storedModels.contains(where: { $0.id == id }) else {
            throw MockError.missing
        }
        return ModelInspectionSummary(
            inputNames: ["input_ids", "style_vector"],
            outputNames: ["waveform"],
            executionProvider: "CoreML Execution Provider"
        )
    }
}

private enum MockError: Error {
    case unsupported
    case missing
}
