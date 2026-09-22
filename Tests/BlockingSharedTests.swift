import Testing
@testable import crashcards

/// The rule that decides whether apps are shielded. Every screen in Focus reads some form of
/// it, so a wrong answer here is either blocking that doesn't happen or a screen claiming a
/// shield that isn't there.
struct BlockingSharedTests {

    // MARK: - Nothing picked

    /// The switch can be on before any app is chosen — the picker is a separate step — and
    /// an empty picker shields nothing, whatever the switch says.
    @Test func nothingIsShieldedUntilAnAppIsPicked() {
        #expect(!BlockingShared.shouldShield(hasSelection: false, isBlocking: true,
                                             isUnlocked: false, hasActiveSchedule: false))
    }

    /// Same for a window that's running: the hours are right, there's just nothing in them.
    @Test func aRunningWindowOverAnEmptyPickerShieldsNothing() {
        #expect(!BlockingShared.shouldShield(hasSelection: false, isBlocking: false,
                                             isUnlocked: false, hasActiveSchedule: true))
    }

    // MARK: - The two ways in

    @Test func theSwitchShieldsOnItsOwn() {
        #expect(BlockingShared.shouldShield(hasSelection: true, isBlocking: true,
                                            isUnlocked: false, hasActiveSchedule: false))
    }

    @Test func aWindowShieldsWithTheSwitchOff() {
        #expect(BlockingShared.shouldShield(hasSelection: true, isBlocking: false,
                                            isUnlocked: false, hasActiveSchedule: true))
    }

    @Test func nothingOnMeansNoShield() {
        #expect(!BlockingShared.shouldShield(hasSelection: true, isBlocking: false,
                                             isUnlocked: false, hasActiveSchedule: false))
    }

    // MARK: - An earned unlock

    /// An unlock outranks both ways in — that's what answering the questions buys.
    @Test func anUnlockLiftsTheShieldTheSwitchPutUp() {
        #expect(!BlockingShared.shouldShield(hasSelection: true, isBlocking: true,
                                             isUnlocked: true, hasActiveSchedule: false))
    }

    @Test func anUnlockLiftsTheShieldAWindowPutUp() {
        #expect(!BlockingShared.shouldShield(hasSelection: true, isBlocking: true,
                                             isUnlocked: true, hasActiveSchedule: true))
    }
}
