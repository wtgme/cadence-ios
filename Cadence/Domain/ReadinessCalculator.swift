import Foundation

/// Daily readiness score, 1..100 (0 = unknown).
final class ReadinessCalculator {

    struct Inputs {
        let sleepScore: Int           // 0..100, 0 = unknown
        let hrvToday: Float           // ms RMSSD, 0 = unknown
        let hrvBaseline: Float        // 14-day mean, 0 = unknown
        let restingHrToday: Int       // bpm, 0 = unknown
        let restingHrBaseline: Float  // 14-day mean, 0 = unknown
        let yesterdayActiveKcal: Float
        let activeKcalBaseline: Float
    }

    struct Result {
        let score: Int        // 0 = unknown; 1..100 otherwise
        let breakdown: String
    }

    func compute(_ inputs: Inputs) -> Result {
        var parts: [(String, Int)] = []
        var score = 50

        if inputs.sleepScore > 0 {
            let sleepComp = max(-25, min(25, Int((Float(inputs.sleepScore - 50) * 0.5).rounded())))
            score += sleepComp
            parts.append(("Sleep", sleepComp))
        }

        if inputs.hrvToday > 0 && inputs.hrvBaseline > 0 {
            let pctDelta = (inputs.hrvToday - inputs.hrvBaseline) / inputs.hrvBaseline
            let hrvComp = max(-15, min(15, Int((pctDelta * 100).rounded())))
            score += hrvComp
            parts.append(("HRV", hrvComp))
        }

        if inputs.restingHrToday > 0 && inputs.restingHrBaseline > 0 {
            let delta = inputs.restingHrBaseline - Float(inputs.restingHrToday)
            let rhrComp = max(-15, min(15, Int((delta * 2).rounded())))
            score += rhrComp
            parts.append(("RHR", rhrComp))
        }

        if inputs.yesterdayActiveKcal > 0 && inputs.activeKcalBaseline > 0 {
            let ratio = inputs.yesterdayActiveKcal / inputs.activeKcalBaseline
            let penalty: Int
            if ratio >= 1.5 { penalty = -10 }
            else if ratio >= 1.2 { penalty = -5 }
            else { penalty = 0 }
            if penalty != 0 {
                score += penalty
                parts.append(("Load", penalty))
            }
        }

        if parts.isEmpty {
            return Result(score: 0, breakdown: "no data")
        }

        let clamped = max(1, min(100, score))
        let breakdown = parts.map { label, delta in
            let sign = delta >= 0 ? "+" : ""
            return "\(label) \(sign)\(delta)"
        }.joined(separator: ", ")
        return Result(score: clamped, breakdown: breakdown)
    }
}
