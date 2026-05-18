import Foundation
import OSLog

final class SongGenerationBackend: GenerationBackend {

    private static let log = Logger(subsystem: "io.cadence.music", category: "SongGenerationBackend")
    private static let maxAttempts = 3

    private let cacheDir: URL
    private let apiSettings: ApiSettingsRepository
    private let session: URLSession

    var name: String { "SongGen-\(apiSettings.current.songGenModel)" }

    init(cacheDir: URL, apiSettings: ApiSettingsRepository) {
        self.cacheDir = cacheDir
        self.apiSettings = apiSettings
        let cfg = URLSessionConfiguration.default
        // The streaming server sends 0x00 heartbeat bytes while warming up; first real
        // audio byte can take 30–60s. URLSession's per-request timeout is the "no bytes
        // for N seconds" budget, not total time — keep it generous.
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 10 * 60
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    func generate(params: SongParams) async -> GenerationResult {
        var lastError = GenerationResult.error(message: "Unknown error")
        for attempt in 1...Self.maxAttempts {
            let result = await attemptGenerate(params: params)
            if case .success = result { return result }
            lastError = result
            if case .error(let msg) = result, !Self.isRetriable(msg) { return result }
            if attempt == Self.maxAttempts { break }
            let backoffMs = UInt64(3000) << (attempt - 1)
            try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
        }
        return lastError
    }

    private func attemptGenerate(params: SongParams) async -> GenerationResult {
        let settings = apiSettings.current
        let body: [String: Any] = [
            "model": settings.songGenModel,
            "prompt": params.descriptions ?? "",
            "lyrics": params.lyric,
            "audio_setting": [
                "sample_rate": 44100,
                "bitrate": 256000,
                "format": "mp3",
            ],
        ]
        let bodyData: Data
        do { bodyData = try JSONSerialization.data(withJSONObject: body, options: []) }
        catch { return .error(message: "JSON encode failed: \(error.localizedDescription)") }

        guard let url = URL(string: settings.songGenBaseUrl) else {
            return .error(message: "Invalid songgen URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if !settings.songGenApiKey.isEmpty {
            req.setValue("Bearer \(settings.songGenApiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        Self.log.debug("\(self.name) → POST /v1/music_generation descriptions=\(params.descriptions ?? "")")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .error(message: "Bad response") }
            if !(200..<300).contains(http.statusCode) {
                let errBody = String(data: data.prefix(300), encoding: .utf8) ?? ""
                let msg = "HTTP \(http.statusCode)" + (errBody.isEmpty ? "" : ": \(errBody)")
                return .error(message: msg)
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .error(message: "Bad JSON")
            }
            if let baseResp = obj["base_resp"] as? [String: Any],
               let statusCode = (baseResp["status_code"] as? NSNumber)?.intValue,
               statusCode != 0 {
                let msg = (baseResp["status_msg"] as? String) ?? "Unknown error"
                return .error(message: msg)
            }
            let dataField = obj["data"] as? [String: Any]
            let hexAudio = (dataField?["audio"] as? String) ?? ""
            if hexAudio.isEmpty {
                return .error(message: "No audio data from \(name)")
            }
            let bytes = Self.bytes(fromHex: hexAudio)
            let file = cacheDir.appendingPathComponent("music_\(Int64(Date().timeIntervalSince1970 * 1000)).mp3")
            do {
                try bytes.write(to: file)
            } catch {
                return .error(message: "Write failed: \(error.localizedDescription)")
            }
            return .success(audioFile: file, params: params)
        } catch {
            return .error(message: "IO error: \(error.localizedDescription)")
        }
    }

    func generateStream(params: SongParams) -> AsyncStream<StreamingChunk> {
        AsyncStream { continuation in
            let task = Task {
                if isDefaultApi() {
                    await streamFromDefaultApi(params: params, continuation: continuation)
                } else {
                    switch await generate(params: params) {
                    case .success(let file, let p):
                        continuation.yield(.audio(file: file, index: 0, params: p))
                        continuation.yield(.complete)
                    case .error(let msg):
                        continuation.yield(.error(message: msg))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func isDefaultApi() -> Bool {
        let a = apiSettings.current.songGenBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let b = BuildConfig.songGenBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return a == b
    }

    private func streamingUrl(baseUrl: String) -> String {
        let trimmed = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        if let range = trimmed.range(of: "/v1/music_generation", options: .backwards) {
            return String(trimmed[..<range.lowerBound]) + "/generate_stream"
        }
        return trimmed + "/generate_stream"
    }

    private func streamFromDefaultApi(params: SongParams, continuation: AsyncStream<StreamingChunk>.Continuation) async {
        let settings = apiSettings.current
        let urlString = streamingUrl(baseUrl: settings.songGenBaseUrl)
        guard let url = URL(string: urlString) else {
            continuation.yield(.error(message: "Invalid streaming URL"))
            return
        }
        var body: [String: Any] = [
            "model": settings.songGenModel,
            "prompt": params.descriptions ?? "",
            "lyrics": params.lyric,
            "audio_setting": [
                "sample_rate": 44100,
                "bitrate": 256000,
                "format": "mp3",
            ],
            "generate_type": params.generateType,
        ]
        if let t = params.autoPromptAudioType { body["auto_prompt_audio_type"] = t }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            continuation.yield(.error(message: "JSON encode failed"))
            return
        }

        for attempt in 1...Self.maxAttempts {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if !settings.songGenApiKey.isEmpty {
                req.setValue("Bearer \(settings.songGenApiKey)", forHTTPHeaderField: "Authorization")
            }
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData

            Self.log.debug("\(self.name) → POST \(urlString) (attempt \(attempt)/\(Self.maxAttempts))")

            let outFile = cacheDir.appendingPathComponent("music_\(Int64(Date().timeIntervalSince1970 * 1000)).mp3")
            var errMsg: String? = nil
            var realBytesWritten: Int64 = 0
            var sawRealByte = false

            do {
                let (bytes, resp) = try await session.bytes(for: req)
                if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    errMsg = "HTTP \(http.statusCode)"
                } else {
                    FileManager.default.createFile(atPath: outFile.path, contents: nil)
                    guard let handle = try? FileHandle(forWritingTo: outFile) else {
                        errMsg = "Cannot open file"
                        break
                    }
                    defer { try? handle.close() }

                    var buf: [UInt8] = []
                    buf.reserveCapacity(16 * 1024)
                    // Three-byte lookahead window for sniffing the "ID3" header. Server
                    // streams leading 0x00 heartbeat bytes; we wait until either an MPEG
                    // frame-sync byte (0xFF) or the literal "ID3" tag header arrives, then
                    // start writing from that point. Mirrors `findMp3Start` in Android.
                    var sniff: [UInt8] = []

                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if !sawRealByte {
                            if byte == 0xFF {
                                sawRealByte = true
                                buf.append(byte)
                            } else if byte == 0x49 /* 'I' */ {
                                // Possible ID3 header start — begin sniffing.
                                sniff = [byte]
                            } else if sniff.count == 1 && byte == 0x44 /* 'D' */ {
                                sniff.append(byte)
                            } else if sniff.count == 2 && byte == 0x33 /* '3' */ {
                                sniff.append(byte)
                                sawRealByte = true
                                buf.append(contentsOf: sniff)
                                sniff.removeAll(keepingCapacity: false)
                            } else {
                                // Reset; this wasn't an ID3/sync byte.
                                sniff.removeAll(keepingCapacity: false)
                            }
                            continue
                        }
                        buf.append(byte)
                        if buf.count >= 16 * 1024 {
                            try handle.write(contentsOf: buf)
                            realBytesWritten += Int64(buf.count)
                            buf.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buf.isEmpty {
                        try handle.write(contentsOf: buf)
                        realBytesWritten += Int64(buf.count)
                    }
                    if !sawRealByte {
                        errMsg = "Stream had no MP3 sync byte — server likely returned an error body"
                    }
                }
            } catch {
                errMsg = "IO error: \(error.localizedDescription)"
            }

            if errMsg == nil && realBytesWritten > 0 {
                continuation.yield(.audio(file: outFile, index: 0, params: params))
                continuation.yield(.complete)
                return
            }

            try? FileManager.default.removeItem(at: outFile)
            let retriable = errMsg != nil && Self.isRetriable(errMsg!)
            if !retriable || attempt == Self.maxAttempts {
                continuation.yield(.error(message: errMsg ?? "Empty stream"))
                return
            }
            let backoffMs = UInt64(3000) << (attempt - 1)
            try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
        }
    }

    func healthCheck() async -> Bool { true }

    private static func isRetriable(_ msg: String) -> Bool {
        msg.hasPrefix("HTTP 429") || msg.hasPrefix("HTTP 500") || msg.hasPrefix("HTTP 502")
            || msg.hasPrefix("HTTP 503") || msg.hasPrefix("HTTP 504") || msg.hasPrefix("IO error")
    }

    private static func bytes(fromHex hex: String) -> Data {
        var data = Data()
        data.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if next > idx, let b = UInt8(hex[idx..<next], radix: 16) {
                data.append(b)
            }
            idx = next
        }
        return data
    }
}
