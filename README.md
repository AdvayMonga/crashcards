# Crash Cards

**Pay for your screen time in flashcards.**

An iOS app that puts your own flashcards between you and the apps you keep opening. Pick the
apps to block, and the system block screen replaces them. To get one back, answer a few
questions correctly — then it unlocks for a set number of minutes and re-locks on its own.

It isn't a parental control. You choose what to block, you set the price, and the only person
it's enforced against is you.

---

## How it works

Blocking is Apple's Screen Time (Family Controls), so it holds at the system level rather than
inside the app — a blocked app shows a shield wherever you open it from.

1. **Study tab** — pick your sets, then Flashcards (tap to flip, swipe or step through) or
   Quiz (graded, scored).
2. **Focus tab** — choose the apps to block, turn blocking on, or schedule the hours it should
   run. Also where you pick which sets the gate may ask from.
3. **Open a blocked app** — the shield appears with an *Answer* button.
4. **Answer** — get enough right and the app opens for your grace window. A background
   extension re-applies the shield when the window expires, with Crash Cards closed.

Quiz mode scores a run as chips × mult, in the spirit of the card games it borrows its look
from: right answers are worth more when they're quick, a streak multiplies them, and a miss
takes the whole multiplier.

## Your cards are just files

A deck is a Markdown file. Nothing is locked in an app database, and the app never edits your
files — it reads them and reports what it couldn't parse.

```markdown
# Deck Title

Front of card :: Back of card

Which planet is closest to the Sun?
- [ ] Venus
- [x] Mercury
- [ ] Mars
- [ ] Earth

Which planet spins backwards compared to the rest?
- [x] Venus
```

Three kinds of card: `::` for a two-sided flip card, a checklist with exactly one `[x]` for
multiple choice, and a checklist where **every** option is `[x]` for an answer you type — each
line being a spelling that counts. Typed answers are forgiving about case, punctuation, a
leading article and accents, but never about the actual word.

You can keep sets inside the app or attach a folder you already own (an Obsidian vault, say).
A deck file can be `.md`, `.markdown`, `.txt` or `.text` for the syntax above, or a `.csv` or
`.tsv` spreadsheet export.

Two starter decks ship with the app so there's something to study on first launch.

## Privacy

No accounts, no server, no analytics, no tracking. Your Screen Time selection stays on the
device in an App Group; your cards stay in your files. The app makes no network requests at
all — asking a chatbot to explain a card opens that chatbot, it doesn't call an API.

## Building it

Requires Xcode 16+ (the tests use Swift Testing) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated and deliberately not committed — `project.yml` is the source of truth.

```sh
brew install xcodegen
xcodegen generate
open crashcards.xcodeproj
```

**Screen Time does not work in the simulator.** The app builds and runs there, and everything
except blocking is usable, but shields only apply on a real device. Running on device needs a
development team set in `project.yml` and, for App Store distribution, Apple's
[Family Controls entitlement](https://developer.apple.com/contact/request/family-controls-distribution),
which is granted by hand per bundle ID.

```sh
xcodebuild test -scheme crashcards -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

169 tests across 21 suites, all pure logic — parsers, scoring, session state, schedules. No UI
tests. CI runs the same command on every pull request.

## Layout

| Target | What it does |
| --- | --- |
| `crashcards` | The app |
| `ShieldConfig` | Draws the system block screen |
| `ShieldAction` | Answers its buttons — opens the app, or closes the blocked one |
| `DeviceActivityMonitorExt` | Re-applies the shield when an unlock window expires |

The three communicate through a shared App Group; `BlockingShared.swift` is the whole of that
channel. iOS 17+, iPhone only.

## Credits

Type is [Pixelify Sans](https://fonts.google.com/specimen/Pixelify+Sans) under the SIL Open
Font License — see `crashcards/Fonts/OFL.txt`. Card art is hand-made pixel art.

## License

MIT — see [LICENSE](LICENSE).
