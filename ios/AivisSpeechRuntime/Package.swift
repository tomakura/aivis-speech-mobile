// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AivisSpeechRuntime",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "AivisSpeechRuntime",
            targets: ["AivisSpeechRuntime"]
        ),
    ],
    dependencies: [
        .package(path: "../AivisMobileCore"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.24.2"),
        .package(url: "https://github.com/apple/swift-testing.git", exact: "6.2.3"),
    ],
    targets: [
        .target(
            name: "AivisSpeechRuntime",
            dependencies: [
                .product(name: "AivisMobileCore", package: "AivisMobileCore"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                "COpenJTalk",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .target(
            name: "COpenJTalk",
            path: "Sources/COpenJTalk",
            exclude: [
                "open_jtalk/CMakeLists.txt",
                "open_jtalk/README",
                "open_jtalk/COPYING",
                "open_jtalk/mecab/COPYING",
                "open_jtalk/mecab/config.h.in",
                "open_jtalk/mecab-naist-jdic",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("open_jtalk/jpcommon"),
                .headerSearchPath("open_jtalk/mecab/src"),
                .headerSearchPath("open_jtalk/mecab2njd"),
                .headerSearchPath("open_jtalk/njd"),
                .headerSearchPath("open_jtalk/njd2jpcommon"),
                .headerSearchPath("open_jtalk/njd_set_accent_phrase"),
                .headerSearchPath("open_jtalk/njd_set_accent_type"),
                .headerSearchPath("open_jtalk/njd_set_digit"),
                .headerSearchPath("open_jtalk/njd_set_long_vowel"),
                .headerSearchPath("open_jtalk/njd_set_pronunciation"),
                .headerSearchPath("open_jtalk/njd_set_unvoiced_vowel"),
                .headerSearchPath("open_jtalk/text2mecab"),
                .define("HAVE_CONFIG_H"),
                .define("DIC_VERSION", to: "102"),
                .define("MECAB_DEFAULT_RC", to: #""dummy""#),
                .define("PACKAGE", to: #""open_jtalk""#),
                .define("VERSION", to: #""1.11""#),
                .define("CHARSET_UTF_8"),
                .define("MECAB_CHARSET", to: #""utf-8""#),
                .define("MECAB_UTF8_USE_ONLY"),
            ],
            cxxSettings: [
                .headerSearchPath("open_jtalk/jpcommon"),
                .headerSearchPath("open_jtalk/mecab/src"),
                .headerSearchPath("open_jtalk/mecab2njd"),
                .headerSearchPath("open_jtalk/njd"),
                .headerSearchPath("open_jtalk/njd2jpcommon"),
                .headerSearchPath("open_jtalk/njd_set_accent_phrase"),
                .headerSearchPath("open_jtalk/njd_set_accent_type"),
                .headerSearchPath("open_jtalk/njd_set_digit"),
                .headerSearchPath("open_jtalk/njd_set_long_vowel"),
                .headerSearchPath("open_jtalk/njd_set_pronunciation"),
                .headerSearchPath("open_jtalk/njd_set_unvoiced_vowel"),
                .headerSearchPath("open_jtalk/text2mecab"),
                .define("HAVE_CONFIG_H"),
                .define("DIC_VERSION", to: "102"),
                .define("MECAB_DEFAULT_RC", to: #""dummy""#),
                .define("PACKAGE", to: #""open_jtalk""#),
                .define("VERSION", to: #""1.11""#),
                .define("CHARSET_UTF_8"),
                .define("MECAB_CHARSET", to: #""utf-8""#),
                .define("MECAB_UTF8_USE_ONLY"),
            ]
        ),
        .testTarget(
            name: "AivisSpeechRuntimeTests",
            dependencies: [
                "AivisSpeechRuntime",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
