import CryptoKit
import Foundation

// The pinned Whisper Large V3 Turbo Core ML model (doc-3 Addendum 8, D4): the
// folder openai_whisper-large-v3-v20240930_turbo of huggingface.co/argmaxinc/
// whisperkit-coreml at one commit, with every file's size and SHA-256 taken from
// the copy verified in LTR-66. A different commit or file is never accepted.
nonisolated enum WhisperModelManifest {
    struct File: Sendable, Equatable {
        var path: String
        var size: Int64
        var sha256: String
    }

    static let modelName = "openai_whisper-large-v3-v20240930_turbo"
    static let revision = "0f63a7800b00dd0226abd051b906c246e1907482"

    static func remoteURL(for file: File) -> URL {
        URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/\(revision)/\(modelName)/\(file.path)")!
    }

    static var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    // True when every file is present with its pinned size. Cheap enough for every
    // launch; the hashes were checked when the files were installed.
    static func isComplete(at folder: URL) -> Bool {
        files.allSatisfy { file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appending(path: file.path).path)
            return (attributes?[.type] as? FileAttributeType) == .typeRegular
                && (attributes?[.size] as? NSNumber)?.int64Value == file.size
        }
    }

    // Size and SHA-256 of the file on disk against the pin.
    static func matches(_ url: URL, _ file: File) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
            size += Int64(chunk.count)
        }
        return size == file.size && hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }

    static let files: [File] = [
        File(path: "AudioEncoder.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "b58d36a7f4a729570b46b424ed8d847baefa07580e6cb9d47773ae738f8b845a"),
        File(path: "AudioEncoder.mlmodelc/coremldata.bin", size: 348, sha256: "ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3"),
        File(path: "AudioEncoder.mlmodelc/metadata.json", size: 1824, sha256: "3f8920fecd553c40dfc978e1b2664cefbac80d97937c2c160e079b37cfa95e13"),
        File(path: "AudioEncoder.mlmodelc/model.mil", size: 7175750, sha256: "9aac7799f12bc5fc414cb0bd6b60536d4fb7723d8bb0d879e3c0ceb220b224aa"),
        File(path: "AudioEncoder.mlmodelc/model.mlmodel", size: 441653, sha256: "c5eb570c19871d7b0c59e0a84718cc9c8cde77a94273886de87e866961262e2c"),
        File(path: "AudioEncoder.mlmodelc/weights/weight.bin", size: 1273974400, sha256: "98daf651a919978e28fe185daf55ce2f70085a8e59fa07fe8a4d08c87d368ae4"),
        File(path: "MelSpectrogram.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce"),
        File(path: "MelSpectrogram.mlmodelc/coremldata.bin", size: 329, sha256: "98efa1e351b759e078c4044668926d32bee886caf7596ae897e08e21da45565a"),
        File(path: "MelSpectrogram.mlmodelc/metadata.json", size: 1850, sha256: "2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f"),
        File(path: "MelSpectrogram.mlmodelc/model.mil", size: 10143, sha256: "c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463"),
        File(path: "MelSpectrogram.mlmodelc/weights/weight.bin", size: 373376, sha256: "009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49"),
        File(path: "TextDecoder.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "47703aed03fbfa5128e118cfe6519024006f953a53e921d66003f1412c27996c"),
        File(path: "TextDecoder.mlmodelc/coremldata.bin", size: 633, sha256: "605dad4099a82cf2c7afe93e6d8e322f1c16d4160ab27bd017ec2517b81c1bdd"),
        File(path: "TextDecoder.mlmodelc/metadata.json", size: 4756, sha256: "de6afb1e8fa1d01568b8d96283ca17af19f6124f151d0fdbdbd5917edc7b4836"),
        File(path: "TextDecoder.mlmodelc/model.mil", size: 132680, sha256: "1a1c2ec962fc7c9d2de9e2e4cf2d3827c8671f86a918b5698c00bf62c322ed3f"),
        File(path: "TextDecoder.mlmodelc/model.mlmodel", size: 113164, sha256: "03b79e4355e814c56239ea809e5d8f6432d70d74256bc9d70c27184fe9fcec48"),
        File(path: "TextDecoder.mlmodelc/weights/weight.bin", size: 343933748, sha256: "47b2703aa37448e09cf2f06e45984fabd5ded4c34ba3400cec38a5294af39dc1"),
        File(path: "TextDecoderContextPrefill.mlmodelc/analytics/coremldata.bin", size: 243, sha256: "97639d36c7b137ea51c3c39b175911788f4d4a601ab03cd67a4b14164c3145e1"),
        File(path: "TextDecoderContextPrefill.mlmodelc/coremldata.bin", size: 380, sha256: "2c159f5c862ec187092ea58e755d8c0b298952e22f3d75da023d7693c1c7389e"),
        File(path: "TextDecoderContextPrefill.mlmodelc/metadata.json", size: 2240, sha256: "eb88dc350fa6748a8bc3fa5fb10958152c138752ebbbac1824d2f99b4c9fc068"),
        File(path: "TextDecoderContextPrefill.mlmodelc/model.mil", size: 4092, sha256: "990ff5052fd817e28ba7c34d9d06d324c69c7c0630b6eaac9cfdf08329dbcb34"),
        File(path: "TextDecoderContextPrefill.mlmodelc/weights/weight.bin", size: 12288192, sha256: "1310070082639173e9d81508c5f220692d489e85655aa6883cc1c7506da7fcfd"),
        File(path: "config.json", size: 1149, sha256: "f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1"),
        File(path: "generation_config.json", size: 2767, sha256: "7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6"),
    ]
}
