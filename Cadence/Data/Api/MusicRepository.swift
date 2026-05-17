import Foundation
import Combine
import OSLog

/// Three-step music generation pipeline:
///   Step 1a — Signal2Style LLM: biometric context → MentalState
///   Step 1b — Signal2Style LLM: MentalState → SongParams
///   Step 2  — GenerationBackend: SongParams → audio file
final class MusicRepository: GenerationRepository {

    private static let log = Logger(subsystem: "io.cadence.music", category: "MusicRepository")

    private let backend: GenerationBackend
    private let tasteMemory: TasteMemoryRepository
    private let userAdjustmentRepository: UserAdjustmentRepository
    private let apiSettings: ApiSettingsRepository

    private let session: URLSession

    private let translatedSongParamsSubject = CurrentValueSubject<SongParams?, Never>(nil)
    private let translatedMentalStateSubject = CurrentValueSubject<MentalState?, Never>(nil)

    var translatedSongParamsPublisher: AnyPublisher<SongParams?, Never> {
        translatedSongParamsSubject.eraseToAnyPublisher()
    }
    var translatedSongParamsValue: SongParams? { translatedSongParamsSubject.value }
    var translatedMentalStatePublisher: AnyPublisher<MentalState?, Never> {
        translatedMentalStateSubject.eraseToAnyPublisher()
    }
    var translatedMentalStateValue: MentalState? { translatedMentalStateSubject.value }

    init(
        backend: GenerationBackend,
        tasteMemory: TasteMemoryRepository,
        userAdjustmentRepository: UserAdjustmentRepository,
        apiSettings: ApiSettingsRepository
    ) {
        self.backend = backend
        self.tasteMemory = tasteMemory
        self.userAdjustmentRepository = userAdjustmentRepository
        self.apiSettings = apiSettings

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 5 * 60
        self.session = URLSession(configuration: cfg)
    }

    private func publishTranslatedParams(_ params: SongParams) {
        Self.log.debug("SongParams: descriptions=\(params.descriptions ?? "nil"), auto_prompt_type=\(params.autoPromptAudioType ?? "nil")")
        translatedSongParamsSubject.send(params)
    }

    // ── Step 1 (public): two-query pipeline with single-query fallback ─────

    func translateMetrics(metricsContext: String) async throws -> SongParams {
        let apiKey = apiSettings.current.signal2StyleApiKey
        if apiKey.isEmpty {
            Self.log.warning("Signal2Style API key missing — using fallback params")
            let fallback = fallbackParams(metricsContext: metricsContext)
            publishTranslatedParams(fallback)
            return fallback
        }
        do {
            // Step 1a
            let mentalState = try await estimateMentalState(metricsContext: metricsContext, apiKey: apiKey)
            translatedMentalStateSubject.send(mentalState)
            Self.log.debug("Step 1a: arousal=\(mentalState?.arousal ?? -1), valence=\(mentalState?.valence ?? -99)")

            if let ms = mentalState, ms.arousal != nil, ms.valence != nil {
                if let params = try await translateMentalStateToParams(mentalState: ms, apiKey: apiKey, previousParams: nil) {
                    publishTranslatedParams(params)
                    return params
                }
                Self.log.warning("Step 1b failed — falling back to single-query")
            } else {
                Self.log.warning("Step 1a failed — falling back to single-query")
            }

            // Single-query fallback
            if let params = try await singleQueryTranslation(metricsContext: metricsContext, apiKey: apiKey) {
                publishTranslatedParams(params)
                return params
            }
            throw URLError(.cannotConnectToHost)
        } catch {
            Self.log.error("Signal2Style translation failed: \(String(describing: error))")
            throw error
        }
    }

    func translateMentalState(_ mentalState: MentalState, previousParams: SongParams?) async -> SongParams? {
        let apiKey = apiSettings.current.signal2StyleApiKey
        if apiKey.isEmpty { return nil }
        do {
            if let p = try await translateMentalStateToParams(mentalState: mentalState, apiKey: apiKey, previousParams: previousParams) {
                publishTranslatedParams(p)
                return p
            }
            return nil
        } catch {
            Self.log.error("Step 1b re-query failed: \(String(describing: error))")
            return nil
        }
    }

    // ── Step 1a ───────────────────────────────────────────────────────────

    private func estimateMentalState(metricsContext: String, apiKey: String) async throws -> MentalState? {
        Self.log.debug("Step 1a: estimating mental state")
        guard let raw = try await callSignal2Style(
            apiKey: apiKey,
            systemPrompt: Self.mentalStateSystem,
            userMessage: "Biometric sensor snapshot:\n\(metricsContext)",
            label: "Step 1a"
        ) else { return nil }
        return parseMentalState(from: extractJson(raw), rawLlmText: raw)
    }

    // ── Step 1b ───────────────────────────────────────────────────────────

    private func translateMentalStateToParams(mentalState: MentalState, apiKey: String, previousParams: SongParams?) async throws -> SongParams? {
        let mentalStateJson = buildMentalStateJson(mentalState)
        let tasteContext = tasteMemory.buildTasteContext()
        let adjustmentHint = userAdjustmentRepository.adjustment.toPromptHint()

        var userMessage = "User's current mental state:\n\(mentalStateJson)"
        if !tasteContext.isEmpty { userMessage += "\n\n\(tasteContext)" }
        if let h = adjustmentHint { userMessage += "\n\n\(h)" }
        if let prev = previousParams {
            var prevDesc = "Previous song: descriptions=\"\(prev.descriptions ?? "")\""
            if let t = prev.autoPromptAudioType { prevDesc += ", auto_prompt_audio_type=\"\(t)\"" }
            prevDesc += ". Choose a noticeably different style — vary the primary genre or instruments."
            userMessage += "\n\n\(prevDesc)"
        }

        Self.log.debug("Step 1b: translating mental state to song params")
        guard let raw = try await callSignal2Style(
            apiKey: apiKey,
            systemPrompt: Self.songParamsFromMentalStateSystem,
            userMessage: userMessage,
            label: "Step 1b"
        ) else { return nil }
        return parseSongParams(from: extractJson(raw))
    }

    // ── Single-query fallback ─────────────────────────────────────────────

    private func singleQueryTranslation(metricsContext: String, apiKey: String) async throws -> SongParams? {
        Self.log.debug("Single-query fallback")
        guard let raw = try await callSignal2Style(
            apiKey: apiKey,
            systemPrompt: Self.systemInstruction,
            userMessage: "Biometric & environmental snapshot:\n\(metricsContext)",
            label: "single-query"
        ) else { return nil }
        return parseSongParams(from: extractJson(raw))
    }

    // ── Signal2Style HTTP with retry ──────────────────────────────────────

    private func callSignal2Style(apiKey: String, systemPrompt: String, userMessage: String, label: String) async throws -> String? {
        let settings = apiSettings.current
        let body: [String: Any] = [
            "model": settings.signal2StyleModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "temperature": 0.7,
            "max_tokens": 128,
            "stream": false,
            "response_format": ["type": "json_object"],
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])

        guard let url = URL(string: "\(settings.signal2StyleBaseUrl)/chat/completions") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://cadence.music", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Cadence", forHTTPHeaderField: "X-Title")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        Self.log.debug("Signal2Style → POST /chat/completions model=\(settings.signal2StyleModel) [\(label)]")

        let maxAttempts = 3
        var lastCode = -1
        var lastErrBody = ""

        for attempt in 1...maxAttempts {
            do {
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return nil }
                if !(200..<300).contains(http.statusCode) {
                    lastCode = http.statusCode
                    lastErrBody = String(data: data.prefix(300), encoding: .utf8) ?? ""
                    Self.log.warning("Signal2Style [\(label)] HTTP \(http.statusCode), \(lastErrBody)")
                } else {
                    if let content = extractContent(data: data), !content.isEmpty {
                        return content
                    }
                    Self.log.warning("Signal2Style [\(label)] empty content")
                }
            } catch {
                lastCode = -1
                Self.log.warning("Signal2Style [\(label)] error: \(String(describing: error))")
            }

            let retriable = lastCode == -1 || lastCode == 429 || (500...599).contains(lastCode)
            if !retriable || attempt == maxAttempts { break }
            let backoffMs = UInt64(2000) << (attempt - 1)
            try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
        }
        Self.log.warning("Signal2Style [\(label)] gave up after \(maxAttempts) attempts")
        return nil
    }

    // ── Parsing ───────────────────────────────────────────────────────────

    private func extractContent(data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        if let content = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
            return content
        }
        if let reasoning = (message["reasoning"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !reasoning.isEmpty {
            Self.log.debug("extractContent: using reasoning field")
            return reasoning
        }
        return nil
    }

    private func extractJson(_ text: String) -> String {
        let fenceOpen = text.range(of: "```")
        let fenceClose = text.range(of: "```", options: .backwards)
        let content: String
        if let open = fenceOpen, let close = fenceClose, open.lowerBound < close.lowerBound {
            let afterOpen = text[open.upperBound...]
            // skip the fence language tag line if present
            if let nl = afterOpen.firstIndex(of: "\n") {
                let start = text.index(after: nl)
                content = String(text[start..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                content = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            content = text
        }
        let braceStart = content.firstIndex(of: "{")
        let braceEnd = content.lastIndex(of: "}")
        if let s = braceStart, let e = braceEnd, s < e {
            return String(content[s...e])
        }
        return content
    }

    private func parseMentalState(from json: String, rawLlmText: String) -> MentalState? {
        guard let data = json.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let arousal = (map["arousal"] as? NSNumber)?.intValue
        let valence = (map["valence"] as? NSNumber)?.intValue
        if arousal == nil && valence == nil { return nil }
        return MentalState(
            arousal: arousal,
            valence: valence,
            stress: (map["stress"] as? NSNumber)?.intValue,
            energy: (map["energy"] as? NSNumber)?.intValue,
            focus: (map["focus"] as? NSNumber)?.intValue,
            mood: (map["mood"] as? String)?.trimmingCharacters(in: .whitespaces),
            rawLlmText: rawLlmText,
        )
    }

    private func buildMentalStateJson(_ ms: MentalState) -> String {
        var map: [String: Any] = [:]
        if let a = ms.arousal { map["arousal"] = a }
        if let v = ms.valence { map["valence"] = v }
        if let s = ms.stress  { map["stress"] = s }
        if let e = ms.energy  { map["energy"] = e }
        if let f = ms.focus   { map["focus"] = f }
        if let m = ms.mood    { map["mood"] = m }
        let data = (try? JSONSerialization.data(withJSONObject: map, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static let autoPromptTypes: Set<String> = [
        "Pop", "Latin", "Rock", "Electronic", "Metal", "Country",
        "R&B/Soul", "Ballad", "Jazz", "World", "Hip-Hop", "Funk", "Soundtrack", "Auto",
    ]

    private func parseSongParams(from json: String) -> SongParams? {
        guard let data = json.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let descriptions: String? = {
            let raw = map["descriptions"] ?? map["tags"]
            if let s = raw as? String {
                let t = s.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }
            if let arr = raw as? [Any] {
                let joined = arr.compactMap { ($0 as? CustomStringConvertible)?.description.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ",")
                return joined.isEmpty ? nil : joined
            }
            return nil
        }()
        guard let descriptions = descriptions else { return nil }

        let autoPromptType: String? = {
            guard let t = (map["auto_prompt_audio_type"] as? String)?.trimmingCharacters(in: .whitespaces) else { return nil }
            return Self.autoPromptTypes.contains(t) ? t : nil
        }()

        return SongParams(
            lyric: ".",
            descriptions: descriptions,
            autoPromptAudioType: autoPromptType,
            generateType: "bgm",
        )
    }

    // ── Step 2 ────────────────────────────────────────────────────────────

    func generateAudioStream(params: SongParams) -> AsyncStream<StreamingChunk> {
        backend.generateStream(params: params)
    }

    // ── Fallback ──────────────────────────────────────────────────────────

    private func fallbackParams(metricsContext: String) -> SongParams {
        func intFrom(_ pattern: String) -> Int? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(metricsContext.startIndex..., in: metricsContext)
            guard let m = re.firstMatch(in: metricsContext, range: range), m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: metricsContext) else { return nil }
            return Int(metricsContext[r])
        }
        func floatFrom(_ pattern: String) -> Float? {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(metricsContext.startIndex..., in: metricsContext)
            guard let m = re.firstMatch(in: metricsContext, range: range), m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: metricsContext) else { return nil }
            return Float(metricsContext[r])
        }

        let hr = intFrom(#"HR: (\d+)"#) ?? 90
        let speed = floatFrom(#"Speed: ([\d.]+)"#) ?? 0
        let readiness = intFrom(#"Readiness: (\d+)"#) ?? 0
        let spo2 = intFrom(#"SpO2: (\d+)"#) ?? 0
        let isRainy = metricsContext.range(of: "rainy", options: .caseInsensitive) != nil ||
                      metricsContext.range(of: "rain", options: .caseInsensitive) != nil

        if spo2 >= 1 && spo2 <= 93 {
            return SongParams(lyric: ".", descriptions: "ambient,slow,peaceful,atmospheric",
                              autoPromptAudioType: "Soundtrack", generateType: "bgm")
        }

        let energyTier: Int
        if readiness >= 76 { energyTier = 4 }
        else if readiness >= 51 { energyTier = 3 }
        else if readiness >= 26 { energyTier = 2 }
        else if readiness >= 1 && readiness <= 25 { energyTier = 1 }
        else if hr > 140 || speed > 8 { energyTier = 4 }
        else if speed > 3 || (hr >= 100 && hr <= 139) { energyTier = 3 }
        else if hr >= 70 && hr <= 99 { energyTier = 2 }
        else { energyTier = 1 }

        let moodTag = isRainy ? "melancholic" : "uplifting"

        switch energyTier {
        case 4:
            return SongParams(lyric: ".", descriptions: "electronic,energetic,powerful,synthesizer,drum machine",
                              autoPromptAudioType: "Electronic", generateType: "bgm")
        case 3:
            return SongParams(lyric: ".", descriptions: "pop,energetic,\(moodTag),bass guitar",
                              autoPromptAudioType: "Pop", generateType: "bgm")
        case 2:
            return SongParams(lyric: ".", descriptions: "jazz,focused,\(moodTag),piano,saxophone",
                              autoPromptAudioType: "Jazz", generateType: "bgm")
        default:
            return SongParams(lyric: ".", descriptions: "ambient,calm,peaceful,dreamy,piano",
                              autoPromptAudioType: "Soundtrack", generateType: "bgm")
        }
    }

    // ── System prompts ────────────────────────────────────────────────────

    private static let mentalStateSystem: String = """
        You are a psychophysiologist trained in the Russell circumplex model of affect.
        Given real-time biometric and environmental sensor data, estimate the user's current
        mental and physiological state. Output ONLY a valid JSON object — no explanation,
        no markdown fences.

        JSON schema:
          "arousal": integer 0–10  (Russell circumplex activation axis.
                     0 = deeply relaxed/asleep, 5 = neutral alertness, 10 = maximally activated/agitated)
          "valence": integer -5 to +5  (Russell circumplex pleasure axis.
                     -5 = very distressed/miserable, 0 = neutral, +5 = very happy/elated)
          "stress":  integer 0–10  (psychological stress. 0 = completely relaxed, 10 = extreme stress)
          "energy":  integer 0–10  (subjective physical energy. 0 = exhausted/depleted, 10 = fully energised)
          "focus":   integer 0–10  (attentional focus. 0 = scattered/drowsy, 10 = deep sustained concentration)
          "mood":    string — one short phrase (e.g. "alert and motivated", "tired but content")

        Interpretation guidelines:
          - Arousal and energy are DIFFERENT. A stressed commuter may have high arousal (tense, elevated HR)
            but LOW energy (poorly rested, depleted). A runner has high arousal AND high energy.
          - Stress and arousal are DIFFERENT. High arousal can be positive (exercise, excitement) or
            negative (anxiety, stress). Use sleep quality, readiness score, time, and context to disambiguate.
          - Focus depends on context: stationary + afternoon + good sleep → focused work;
            stationary + night + low readiness → drowsy.
          - The "Music guidance" line is a mechanical heuristic. You may DISAGREE with it when the
            biometric context suggests a different state. For example: if readiness says "High" but
            sleep was poor and it is Monday morning during a commute, the user is likely tired and
            stressed, not energised.
          - Use the FULL range of each scale. Do not cluster everything around 5.

        Key signals:
          - Heart rate > 100 at rest → stress or post-exercise; > 140 → active exercise
          - Low readiness + high activity → pushing through fatigue
          - Deep sleep < 10% → impaired physical recovery (lower energy)
          - REM < 15% → impaired cognitive function (lower focus)
          - SpO2 < 94% → physiological distress (high stress, low energy)
          - Late night (after 9 pm) → circadian low (lower arousal/energy)
          - Rain/overcast → lower valence; sun/clear → higher valence
          - Weekday commute → more stress than weekend leisure

        UNKNOWN HR HANDLING:
          When HR is "unknown" (user has no wearable / no recent samples), do NOT default arousal
          to 5. Use Activity, GPS speed, time of day, and step count as the primary arousal proxies:
            - Stationary + no activity + low steps today → arousal 2–3
            - Walking / casual GPS speed → arousal 3–5
            - Running / Cycling / Workout scene → arousal 6–8
            - Late evening / night → cap arousal at 3 regardless of other signals
          When HR is unknown, lean conservative: pick the LOWER end of each range above. We can
          always nudge up later if HR data appears.
        """

    private static let songParamsFromMentalStateSystem: String = """
        You are an expert music therapist and producer. Given a user's current mental and
        physiological state, select instrumental music parameters for an AI music generation model.
        Output ONLY a valid JSON object — no explanation, no markdown fences.

        JSON fields:
          "descriptions": 3–6 comma-separated lowercase tags from these pools:
              Genre    : pop, jazz, rock, electronic, ambient, classical, funk, r&b, hip-hop, folk, new-age, blues
              Emotion  : energetic, calm, peaceful, uplifting, melancholic, introspective, focused,
                         euphoric, powerful, dreamy, relaxing, sad, cheerful, romantic
              Instrument: piano, synthesizer, electric guitar, acoustic guitar, drums, drum machine,
                          bass guitar, strings, violin, saxophone, trumpet, flute
          "auto_prompt_audio_type": exactly one of:
              Pop, Latin, Rock, Electronic, Metal, Country, R&B/Soul, Ballad, Jazz, World,
              Hip-Hop, Funk, Soundtrack, Auto
              NOTE: "Ambient" is NOT valid — use Soundtrack instead.

        DECISION PROCEDURE — follow this exact priority order:

        PRIORITY 1 — STRESS OVERRIDE (mandatory):
          If stress >= 7: select a calming genre ONLY.
            Allowed genres    : ambient, classical, jazz, new-age, folk
            Allowed emotions  : calm, peaceful, relaxing, dreamy, introspective
            Allowed instruments: piano, strings, acoustic guitar, flute, saxophone
            auto_prompt_audio_type MUST be one of: Soundtrack, Jazz, Ballad
            Do NOT use: electronic, rock, pop, funk, drums, drum machine, energetic, powerful, euphoric
            This rule applies REGARDLESS of arousal or energy values.

        PRIORITY 2 — ISO-PRINCIPLE (match then nudge):
          Match music energy to current arousal; nudge valence gently upward. Do not jump more
          than one tier from current arousal.
            arousal 8–10 → electronic, rock, pop, hip-hop, or funk + energetic/powerful/euphoric + drums/synthesizer/electric guitar
            arousal 5–7  → pop, funk, r&b, hip-hop, or blues + focused/uplifting/cheerful + bass guitar/synthesizer/piano
            arousal 3–4  → jazz, folk, classical, or ambient + focused/cheerful/introspective + piano/saxophone/acoustic guitar
                           INSTRUMENT RESTRICTION: minimise percussion. No drum machine.
            arousal 0–2  → ambient, classical, or new-age + calm/peaceful/dreamy + piano/strings/flute
                           INSTRUMENT RESTRICTION: piano, strings, flute, or acoustic guitar ONLY.

        PRIORITY 3 — MODIFIERS:
          - If focus >= 7: include "focused". Prefer piano, strings, acoustic guitar (minimal percussion).
          - If energy <= 3 AND arousal >= 5: dial back one arousal tier.
          - If valence <= -2: include exactly one of "melancholic" or "introspective" (not both).
          - If valence >= 3: include exactly one of "uplifting" or "euphoric" (not both).

        CONSTRAINTS:
          - Never combine contradictory emotions: calm+energetic, peaceful+powerful, dreamy+euphoric.
          - Encode tempo through genre — do NOT use words like fast, slow, mid-tempo, driving, upbeat.
          - Include at least one instrument tag and at least one emotion tag.
          - descriptions must be a single comma-separated string, not an array.
        """

    private static let systemInstruction: String = """
        You are a biometric-aware music producer. Translate a real-time sensor snapshot into
        music style parameters for an AI music generation model. Output ONLY a valid JSON
        object — no explanation, no markdown fences.

        JSON fields:
          "descriptions": 3–6 comma-separated lowercase tags from these dimensions:
              Genre    : pop, jazz, rock, electronic, ambient, classical, funk, r&b, hip-hop, folk, new-age, blues
              Emotion  : energetic, calm, peaceful, uplifting, melancholic, introspective, focused,
                         euphoric, powerful, dreamy, relaxing, sad, cheerful, romantic
              Instrument: piano, synthesizer, electric guitar, acoustic guitar, drums, drum machine,
                          bass guitar, strings, violin, saxophone, trumpet, flute
          "auto_prompt_audio_type": MUST be exactly one of:
              Pop, Latin, Rock, Electronic, Metal, Country, R&B/Soul, Ballad, Jazz, World, Hip-Hop, Funk, Soundtrack, Auto
              NOTE: "Ambient" is NOT valid — use Soundtrack instead.

        Rules: follow the Energy Tier in Music guidance exactly. Never mix contradictory emotions.
        """
}
