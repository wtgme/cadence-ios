import Foundation

/// Builds a raw metrics context string from sensor data. NOT the final music prompt —
/// it gets passed to the AI Producer which translates it into structured song parameters.
final class PromptBuilder {

    func buildMetricsContext(state: SensorState, scene: Scene?) -> String {
        let activityLabel: String
        switch scene {
        case .running:   activityLabel = "Running"
        case .cycling:   activityLabel = "Cycling"
        case .walking:   activityLabel = "Walking"
        case .commuting: activityLabel = "Travelling"
        case .workout:   activityLabel = "Working Out"
        case .focus:     activityLabel = "Focus/Study"
        case .party:     activityLabel = "Party/Social"
        case .resting:   activityLabel = "Resting"
        case .none:      activityLabel = "Stationary"
        }

        let sleepLabel: String
        if state.sleepScore == 0 { sleepLabel = "unknown" }
        else if state.sleepScore >= 80 { sleepLabel = "Well-rested" }
        else if state.sleepScore >= 50 { sleepLabel = "Average sleep" }
        else { sleepLabel = "Poorly rested" }

        let dayLabel: String
        switch state.dayOfWeek {
        case 1: dayLabel = "Sunday"
        case 2: dayLabel = "Monday"
        case 3: dayLabel = "Tuesday"
        case 4: dayLabel = "Wednesday"
        case 5: dayLabel = "Thursday"
        case 6: dayLabel = "Friday"
        default: dayLabel = "Saturday"
        }
        let isWeekend = state.dayOfWeek == 1 || state.dayOfWeek == 7

        let amPm = state.hourOfDay < 12 ? "am" : "pm"
        let hour12: Int = {
            let h = state.hourOfDay % 12
            return h == 0 ? 12 : h
        }()
        let minuteStr = state.minuteOfHour < 10 ? "0\(state.minuteOfHour)" : "\(state.minuteOfHour)"
        let timeStr = "\(hour12):\(minuteStr)\(amPm)"

        let timeLabel: String
        switch state.hourOfDay {
        case 5...8:   timeLabel = "Early morning"
        case 9...11:  timeLabel = "Morning"
        case 12...13: timeLabel = "Midday"
        case 14...17: timeLabel = "Afternoon"
        case 18...20: timeLabel = "Evening"
        default:      timeLabel = "Night"
        }

        let weatherMood: String
        let w = state.weather.lowercased()
        if w.contains("sun") || w.contains("clear") {
            weatherMood = "sunny — favour major key, bright valence, higher energy"
        } else if w.contains("rain") || w.contains("storm") {
            weatherMood = "rainy — favour minor key, introspective, lower energy"
        } else if w.contains("cloud") || w.contains("overcast") {
            weatherMood = "overcast — soothing, acoustic, neutral valence"
        } else {
            weatherMood = state.weather
        }

        var musicGuidance = ""

        // 1. SpO2 safety override.
        if state.spo2 >= 1 && state.spo2 <= 93 {
            musicGuidance += "⚠ SpO2 low (\(state.spo2)%) — use <60 BPM, nature-inspired ambient only. "
        }

        // 2. Iso-principle: match arousal first, readiness as ceiling.
        let readinessTier: Int
        switch state.readinessScore {
        case 76...: readinessTier = 4
        case 51...75: readinessTier = 3
        case 26...50: readinessTier = 2
        case 1...25:  readinessTier = 1
        default:      readinessTier = 0
        }
        let contextCap: Int
        if state.hourOfDay >= 21 || state.hourOfDay < 5 { contextCap = 1 }
        else if state.hourOfDay >= 18 && state.hourOfDay <= 20 { contextCap = 2 }
        else if scene == .party { contextCap = 4 }
        else if scene == .resting || scene == nil { contextCap = 2 }
        else if scene == .focus { contextCap = 2 }
        else { contextCap = 4 }

        let hrUnknown = state.heartRate <= 0
        let sedentary = scene == .resting || scene == .focus || scene == nil
        let cappedForUnknownHr = (hrUnknown && sedentary) ? max(contextCap - 1, 1) : contextCap
        let effectiveTier = readinessTier > 0 ? min(readinessTier, cappedForUnknownHr) : cappedForUnknownHr

        let tierLabel: String
        let bpmNote: String
        switch effectiveTier {
        case 4: tierLabel = "Very High"; bpmNote = "target 145+ BPM (sympathetic drive)"
        case 3: tierLabel = "High";      bpmNote = "target 110–130 BPM (flow state)"
        case 2: tierLabel = "Medium";    bpmNote = "target 90–110 BPM (active recovery)"
        default: tierLabel = "Low";      bpmNote = "target <60 BPM (parasympathetic rebound)"
        }

        if readinessTier > 0 && readinessTier != effectiveTier {
            musicGuidance += "Readiness capacity: \(tierName(readinessTier)) — capped to \(tierLabel) by current context (\(bpmNote)). "
        } else {
            musicGuidance += "Energy tier: \(tierLabel) — \(bpmNote). "
        }

        // 3. Sleep architecture modifiers (percentages 0–100).
        if state.sleepRemPct > 0 && state.sleepRemPct < 15 {
            musicGuidance += "Low REM sleep (\(Int(state.sleepRemPct))%) — use simple melodies, high melodic clarity. "
        }
        if state.sleepDeepPct > 0 && state.sleepDeepPct < 10 {
            musicGuidance += "Low deep sleep (\(Int(state.sleepDeepPct))%) — reduce percussive density, avoid heavy drums. "
        }
        musicGuidance = musicGuidance.trimmingCharacters(in: .whitespaces)

        var out = ""
        out += "Activity: \(activityLabel), "
        out += "GPS Speed: \(fmt1(state.speedKmh)) km/h, "
        out += "Weather: \(weatherMood), "
        out += "HR: \(state.heartRate > 0 ? "\(state.heartRate) bpm" : "unknown"), "
        if state.spo2 > 0 { out += "SpO2: \(state.spo2)%, " }
        out += "Location: \(fmt4(state.latitude)), \(fmt4(state.longitude)), "
        out += "Today: \(state.stepsToday) steps, \(state.activityMinutesToday) mins, \(fmt0(state.caloriesBurned)) kcal, "
        if state.readinessScore > 0 {
            out += "Readiness: \(state.readinessScore)/100 (\(state.readinessBreakdown)), "
        }
        var sleepDetail = sleepLabel
        if state.sleepScore > 0 { sleepDetail += " (\(state.sleepScore)/100)" }
        if state.sleepDeepPct > 0 { sleepDetail += ", deep \(Int(state.sleepDeepPct))%" }
        if state.sleepRemPct > 0 { sleepDetail += ", REM \(Int(state.sleepRemPct))%" }
        out += "Sleep: \(sleepDetail), "
        out += "Time: \(timeLabel) (\(timeStr)), "
        out += "Day: \(dayLabel)\(isWeekend ? " (weekend)" : " (weekday)")"
        if !musicGuidance.isEmpty {
            out += "\nMusic guidance: \(musicGuidance)"
        }
        return out
    }

    private func tierName(_ tier: Int) -> String {
        switch tier {
        case 4: return "Very High"
        case 3: return "High"
        case 2: return "Medium"
        default: return "Low"
        }
    }

    private func fmt0(_ v: Float) -> String { String(format: "%.0f", v) }
    private func fmt1(_ v: Float) -> String { String(format: "%.1f", v) }
    private func fmt4(_ v: Double) -> String { String(format: "%.4f", v) }
}
