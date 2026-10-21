import Foundation

struct BERTSessionAssets: Sendable, Equatable {
    let modelURL: URL
    let tokenizerURL: URL
}

extension StyleBertVITS2SpeechEngine.AssetConfiguration {
    fileprivate static let defaultRepositoryID = "tsukumijima/deberta-v2-large-japanese-char-wwm-onnx"
    fileprivate static let defaultRevision = "d701ec67708287b20d2063270f6b535e6eed09ab"

    var resolvedAssets: BERTSessionAssets? {
        let fileManager = FileManager.default
        if let bundledAssets = Self.bundledAssets(fileManager: fileManager) {
            return bundledAssets
        }

        for directory in candidateDirectories {
            if let assets = Self.assets(in: directory, fileManager: fileManager) {
                return assets
            }
        }
        return nil
    }

    var isInstalled: Bool {
        resolvedAssets != nil
    }

    private var candidateDirectories: [URL] {
        var directories: [URL] = [cacheDirectory]

        if let environmentPath = ProcessInfo.processInfo.environment["AIVIS_BERT_CACHE_DIR"], !environmentPath.isEmpty {
            directories.append(URL(fileURLWithPath: environmentPath, isDirectory: true))
        }

        let userAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directories.append(
            userAppSupport
                .appendingPathComponent("AivisSpeech-Engine", isDirectory: true)
                .appendingPathComponent("BertModelCaches", isDirectory: true)
        )

        directories.append(
            cacheDirectory
                .appendingPathComponent(
                    "models--\(Self.defaultRepositoryID.replacingOccurrences(of: "/", with: "--"))",
                    isDirectory: true
                )
                .appendingPathComponent("snapshots", isDirectory: true)
                .appendingPathComponent(Self.defaultRevision, isDirectory: true)
        )

        return directories
    }

    private static func bundledAssets(fileManager: FileManager) -> BERTSessionAssets? {
        if let modelURL = Bundle.module.url(forResource: "model_fp16", withExtension: "onnx"),
           let tokenizerURL = Bundle.module.url(forResource: "tokenizer", withExtension: "json"),
           fileManager.fileExists(atPath: modelURL.path),
           fileManager.fileExists(atPath: tokenizerURL.path) {
            return BERTSessionAssets(modelURL: modelURL, tokenizerURL: tokenizerURL)
        }

        if let directory = Bundle.module.url(forResource: "BERTAssets", withExtension: nil),
           let assets = assets(in: directory, fileManager: fileManager) {
            return assets
        }

        return nil
    }

    private static func assets(in directory: URL, fileManager: FileManager) -> BERTSessionAssets? {
        let directModelURL = directory.appendingPathComponent("model_fp16.onnx")
        let directTokenizerURL = directory.appendingPathComponent("tokenizer.json")
        if fileManager.fileExists(atPath: directModelURL.path),
           fileManager.fileExists(atPath: directTokenizerURL.path) {
            return BERTSessionAssets(modelURL: directModelURL, tokenizerURL: directTokenizerURL)
        }

        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        var modelURL: URL?
        var tokenizerURL: URL?
        for case let url as URL in enumerator {
            switch url.lastPathComponent {
            case "model_fp16.onnx":
                modelURL = url
            case "tokenizer.json":
                tokenizerURL = url
            default:
                continue
            }

            if let modelURL, let tokenizerURL {
                return BERTSessionAssets(modelURL: modelURL, tokenizerURL: tokenizerURL)
            }
        }

        return nil
    }
}
