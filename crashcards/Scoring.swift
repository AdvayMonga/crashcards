import Foundation
import Observation

/// What a card is worth, and what multiplies it.
///
/// Chips come from the answer itself — being right, and being quick about it. Mult comes
/// from the run of right answers behind you. The score is the product of the two, which is
/// the one arithmetic this app's whole look is borrowed from.
enum ScoreRules {
    /// What any correct answer is worth before speed or streak.
    static let baseChips = 10

    /// Answer inside `fast` and the card pays the most; inside `brisk`, something; after
    /// that, nothing extra. Fixed thresholds rather than a curve — a tier lands as an event
    /// you can see, where a curve just quietly pays you less.
    static let fastSeconds: TimeInterval = 3
    static let briskSeconds: TimeInterval = 8
    static let fastChips = 15
    static let briskChips = 5

    /// A flawless run pays this per card, so a clean run of forty is worth more than a
    /// clean run of three.
    static let perfectChipsPerCard = 50

    /// Days in a row studied, as the mult every run opens on. This is the only place the
    /// history feeds back into play.
    static func baseMult(dayStreak: Int) -> Double {
        switch dayStreak {
        case 7...: return 2
        case 3...6: return 1.5
        default: return 1
        }
    }

    static func speedChips(_ elapsed: TimeInterval) -> Int {
        if elapsed <= fastSeconds { return fastChips }
        if elapsed <= briskSeconds { return briskChips }
        return 0
    }
}

/// One quiz run's score, built answer by answer.
///
/// Only quiz mode keeps one of these. Flashcards isn't graded, and the unlock gate is a toll
/// rather than a game — both stay out of it.
@Observable
final class ScoreRun {
    /// Where the mult starts, earned by turning up on consecutive days.
    let baseMult: Double

    private(set) var total = 0
    private(set) var streak = 0
    private(set) var bestStreak = 0
    private(set) var answered = 0
    private(set) var missed = 0
    /// What the last answer paid, for the figure that flies off the card.
    private(set) var lastGain = 0
    private(set) var perfectBonus = 0

    private var finished = false

    init(dayStreak: Int = 0) {
        baseMult = ScoreRules.baseMult(dayStreak: dayStreak)
    }

    /// The mult the answer being scored right now pays at. `record` bumps the streak before
    /// reading this, so the first right answer pays the base rather than already doubled.
    var mult: Double { baseMult + Double(max(streak - 1, 0)) }

    /// The mult on offer for the answer about to be given — what the header shows while you
    /// are still deciding.
    var pendingMult: Double { baseMult + Double(streak) }

    var isPerfect: Bool { answered > 0 && missed == 0 }

    /// Score one answer and hand back what it paid.
    @discardableResult
    func record(correct: Bool, elapsed: TimeInterval = .infinity) -> Int {
        answered += 1
        guard correct else {
            // A miss takes the whole mult, not a slice of it. That's the tension.
            streak = 0
            missed += 1
            lastGain = 0
            return 0
        }

        streak += 1
        bestStreak = max(bestStreak, streak)
        let chips = ScoreRules.baseChips + ScoreRules.speedChips(elapsed)
        let gain = Int((Double(chips) * mult).rounded())
        total += gain
        lastGain = gain
        return gain
    }

    /// Close the run, paying the perfect bonus if it earned one. Called once, when the last
    /// question lands.
    @discardableResult
    func finish() -> Int {
        guard !finished, isPerfect else { finished = true; return 0 }
        finished = true
        perfectBonus = answered * ScoreRules.perfectChipsPerCard
        total += perfectBonus
        return perfectBonus
    }
}
