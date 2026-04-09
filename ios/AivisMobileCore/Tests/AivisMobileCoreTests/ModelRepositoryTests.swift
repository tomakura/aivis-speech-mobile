import Foundation
import Testing
@testable import AivisMobileCore

struct ModelRepositoryTests {
    @Test
    func fixtureMetadataInstallsAndTransitions() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("sample.aivmx.json")
        try FixtureBootstrap.loadFixtureData(
            "shared/fixtures/models/aivmx-metadata.sample.json"
        ).write(to: sourceURL, options: .atomic)

        let repositoryURL = temporaryDirectory.appendingPathComponent("repository", isDirectory: true)
        let repository = FileModelRepository(rootDirectory: repositoryURL)

        let installed = try await repository.installModel(fromFile: sourceURL)
        let expectedManifest = try FixtureBootstrap.loadAIVMXMetadataEnvelope().manifest

        #expect(installed.id == expectedManifest.uuid)
        #expect(installed.name == expectedManifest.name)
        #expect(installed.version == expectedManifest.version)
        #expect(installed.loadState == .installed)

        let snapshot = try await repository.snapshot()
        #expect(snapshot.records.count == 1)
        #expect(snapshot.records.first?.manifest.uuid == expectedManifest.uuid)
        #expect(snapshot.records.first?.manifest.name == expectedManifest.name)
        #expect(snapshot.records.first?.manifest.runtimeDescriptor?.availableStyleIDs == [0])
        #expect(snapshot.records.first?.manifest.runtimeDescriptor?.vectorProfiles.isEmpty == false)
        #expect(snapshot.records.first?.manifest.runtimeDescriptor?.notes.isEmpty == false)

        try await repository.loadModel(id: installed.id)
        let loadedRecord = try await repository.record(id: installed.id)
        #expect(loadedRecord.loadState.loaded)

        try await repository.unloadModel(id: installed.id)
        let unloadedRecord = try await repository.record(id: installed.id)
        #expect(!unloadedRecord.loadState.loaded)
        #expect(!unloadedRecord.loadState.active)

        let updated = try await repository.updateModel(id: installed.id)
        #expect(updated.id == installed.id)

        try await repository.removeModel(id: installed.id)
        let emptySnapshot = try await repository.snapshot()
        #expect(emptySnapshot.records.isEmpty)
    }

    @Test
    func repositoryReportsInstalledModelsInNameOrder() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let repositoryURL = temporaryDirectory.appendingPathComponent("repository", isDirectory: true)
        let repository = FileModelRepository(rootDirectory: repositoryURL)

        let fixture = try FixtureBootstrap.loadAIVMXMetadataEnvelope()
        let secondSourceURL = temporaryDirectory.appendingPathComponent("second.aivmx.json")
        let secondEnvelopeData = try JSONEncoder().encode(
            AIVMXMetadataEnvelope(
                manifest: AIVMXManifest(
                    uuid: UUID(),
                    name: "ZZZ Companion",
                    version: fixture.manifest.version,
                    modelArchitecture: fixture.manifest.modelArchitecture,
                    modelFormat: fixture.manifest.modelFormat,
                    speakers: fixture.manifest.speakers
                ),
                loadState: fixture.loadState
            )
        )
        try secondEnvelopeData.write(to: secondSourceURL, options: .atomic)

        let firstSourceURL = temporaryDirectory.appendingPathComponent("aaa.aivmx.json")
        try FixtureBootstrap.loadFixtureData(
            "shared/fixtures/models/aivmx-metadata.sample.json"
        ).write(to: firstSourceURL, options: .atomic)

        _ = try await repository.installModel(fromFile: secondSourceURL)
        _ = try await repository.installModel(fromFile: firstSourceURL)

        let installed = try await repository.installedModels()
        #expect(installed.count == 2)
        #expect(installed[0].name == "Sample Voice Model")
        #expect(installed[1].name == "ZZZ Companion")
    }

    @Test
    func sidecarMetadataIsUsedForOnnxInstall() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let modelURL = temporaryDirectory.appendingPathComponent("seed.onnx")
        try Data("placeholder".utf8).write(to: modelURL, options: .atomic)

        let sidecarURL = temporaryDirectory.appendingPathComponent("seed.json")
        try FixtureBootstrap.loadFixtureData("shared/fixtures/models/aivmx-metadata.sample.json")
            .write(to: sidecarURL, options: .atomic)

        let repositoryURL = temporaryDirectory.appendingPathComponent("repository", isDirectory: true)
        let repository = FileModelRepository(rootDirectory: repositoryURL)

        let installed = try await repository.installModel(fromFile: modelURL)

        #expect(installed.name == "Sample Voice Model")
        #expect(installed.manifest?.modelArchitecture == "Style-Bert-VITS2")
        #expect(installed.manifest?.runtimeDescriptor?.availableStyleIDs == [0])
    }

    @Test
    func embeddedAivmxMetadataIsUsedWithoutSidecar() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let modelURL = temporaryDirectory.appendingPathComponent("embedded.aivmx")
        try makeEmbeddedAIVMXPayload().write(to: modelURL, options: .atomic)

        let repositoryURL = temporaryDirectory.appendingPathComponent("repository", isDirectory: true)
        let repository = FileModelRepository(rootDirectory: repositoryURL)

        let installed = try await repository.installModel(fromFile: modelURL)

        #expect(installed.name == "Embedded Sample")
        #expect(installed.version == "1.2.3")
        #expect(installed.manifest?.modelFormat == "ONNX")
        #expect(installed.manifest?.modelArchitecture == "Style-Bert-VITS2 (JP-Extra)")
        #expect(installed.manifest?.runtimeDescriptor?.hyperParameters.outputSamplingRate == 44_100)
        #expect(installed.manifest?.runtimeDescriptor?.availableStyleIDs == [0])
        #expect(installed.manifest?.runtimeDescriptor?.vectorProfiles.first?.dimension == 256)
        #expect(
            installed.manifest?.runtimeDescriptor?.notes.contains(
                "Embedded AIVMX metadata extracted from ONNX metadata_props."
            ) == true
        )
    }
}

private func makeEmbeddedAIVMXPayload() throws -> Data {
    let manifestJSON = """
    {
      "manifest_version": "1.0",
      "name": "Embedded Sample",
      "description": "",
      "creators": [],
      "license": null,
      "model_architecture": "Style-Bert-VITS2 (JP-Extra)",
      "model_format": "ONNX",
      "training_epochs": 12,
      "training_steps": 3456,
      "uuid": "6f37ba4d-7f52-4cf4-a717-6488cb19e270",
      "version": "1.2.3",
      "speakers": [
        {
          "name": "Embedded Speaker",
          "icon": "data:image/png;base64,AA==",
          "supported_languages": ["ja"],
          "uuid": "853dc9d3-fbce-43ff-b61f-1df6001e554a",
          "local_id": 0,
          "styles": [
            {
              "name": "ノーマル",
              "icon": null,
              "local_id": 0,
              "voice_samples": []
            }
          ]
        }
      ]
    }
    """

    let hyperParametersJSON = """
    {
      "model_name": "Embedded Sample",
      "version": "2.0-JP-Extra",
      "data": {
        "sampling_rate": 44100,
        "spk2id": {
          "Embedded Speaker": 0
        },
        "style2id": {
          "ノーマル": 0
        }
      },
      "model": {
        "gin_channels": 256
      }
    }
    """

    let rawMetadata = [
        "aivm_manifest": manifestJSON,
        "aivm_hyper_parameters": hyperParametersJSON,
        "aivm_style_vectors": Data("not-a-real-npy".utf8).base64EncodedString(),
    ]

    var payload = Data()
    for (key, value) in rawMetadata.sorted(by: { $0.key < $1.key }) {
        let entry = makeLengthDelimitedField(
            fieldNumber: 1,
            value: Data(key.utf8)
        ) + makeLengthDelimitedField(
            fieldNumber: 2,
            value: Data(value.utf8)
        )
        payload += makeLengthDelimitedField(fieldNumber: 14, value: entry)
    }
    return payload
}

private func makeLengthDelimitedField(fieldNumber: UInt64, value: Data) -> Data {
    var data = encodeVarint((fieldNumber << 3) | 2)
    data += encodeVarint(UInt64(value.count))
    data += value
    return data
}

private func encodeVarint(_ value: UInt64) -> Data {
    var remaining = value
    var bytes: [UInt8] = []

    repeat {
        var byte = UInt8(remaining & 0x7f)
        remaining >>= 7
        if remaining != 0 {
            byte |= 0x80
        }
        bytes.append(byte)
    } while remaining != 0

    return Data(bytes)
}
