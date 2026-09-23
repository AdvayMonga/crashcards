import SwiftUI

// MARK: - Transitions

extension AnyTransition {
    /// How a screen arrives: it grows into place. Deliberately not a slide — a page sliding
    /// in from the edge is the one motion that reads as "stock iOS" no matter how it's styled.
    static var dealIn: AnyTransition {
        .scale(scale: 0.92).combined(with: .opacity)
    }

    /// How a single card arrives: thrown onto the table from below, slightly crooked.
    static var dealtCard: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: DealOffset(y: 90, angle: -7), identity: DealOffset()),
            removal: .modifier(active: DealOffset(y: -60, angle: 5), identity: DealOffset()))
        .combined(with: .opacity)
    }
}

private struct DealOffset: ViewModifier {
    var y: CGFloat = 0
    var angle: Double = 0

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(angle)).offset(y: y)
    }
}

// MARK: - The screen stack

extension View {
    /// A screen that takes over, with our transition instead of a push or a cover.
    @ViewBuilder
    func screenLayer<Item: Identifiable, Screen: View>(
        item: Binding<Item?>,
        @ViewBuilder screen: @escaping (Item) -> Screen
    ) -> some View {
        ZStack {
            self
            if let value = item.wrappedValue {
                screen(value)
                    .transition(.dealIn)
                    .zIndex(1)
            }
        }
        .animation(Motion.deal, value: item.wrappedValue != nil)
    }

    @ViewBuilder
    func screenLayer<Screen: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder screen: @escaping () -> Screen
    ) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue {
                screen()
                    .transition(.dealIn)
                    .zIndex(1)
            }
        }
        .animation(Motion.deal, value: isPresented.wrappedValue)
    }
}

// MARK: - Modal

/// A panel that pops up over the table: the replacement for `.sheet`.
///
/// It grows from the middle rather than sliding up from the bottom, and the table behind it
/// darkens rather than shrinking away. Tapping the scrim closes it, like a sheet's swipe.
struct CrashModal<Body: View>: View {
    let title: String
    var confirm: (label: String, enabled: Bool, action: () -> Void)?
    let onCancel: () -> Void
    @ViewBuilder var content: Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                bar
                Rectangle().fill(Brand.outline).frame(height: Brand.stroke)
                ScrollView {
                    content
                        .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .background(Brand.tableDeep)
            .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(Brand.outline, lineWidth: Brand.stroke))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
            .padding(.horizontal, 14)
            .padding(.vertical, 40)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Button("Cancel") { onCancel() }
                .buttonStyle(CrashButton(kind: .ghost, tint: Brand.inkDim, fullWidth: false))

            Spacer(minLength: 4)

            Text(title)
                .font(.brandLabel)
                .foregroundStyle(Brand.ink)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let confirm {
                Button(confirm.label) { confirm.action() }
                    .buttonStyle(CrashButton(kind: .ghost, tint: Brand.gold, fullWidth: false))
                    .disabled(!confirm.enabled)
            } else {
                Color.clear.frame(width: 60, height: 1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Brand.surface)
    }
}

// MARK: - Alert

/// One message, one way out. Replaces `.alert`.
struct CrashAlert: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                PixelIcon(glyph: .warning, size: 36, color: Brand.orange)
                Text(title)
                    .font(.brandLabel)
                    .foregroundStyle(Brand.ink)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.reading(15))
                    .foregroundStyle(Brand.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("OK") { onDismiss() }
                    .buttonStyle(.solid)
                    .padding(.top, 4)
            }
            .padding(22)
            .slab(Brand.surface, radius: Brand.cardRadius)
            .padding(.horizontal, 36)
        }
        .transition(.scale(scale: 0.88).combined(with: .opacity))
    }
}

/// A choice of actions, stacked. Replaces `.confirmationDialog`.
struct CrashDialog<Choices: View>: View {
    let title: String
    var message: String?
    let onCancel: () -> Void
    @ViewBuilder var choices: Choices

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.brandLabel)
                        .foregroundStyle(Brand.gold)
                    if let message {
                        Text(message)
                            .font(.reading(14))
                            .foregroundStyle(Brand.inkDim)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                choices

                Button("Cancel") { onCancel() }
                    .buttonStyle(CrashButton(kind: .soft, tint: Brand.inkDim))
                    .padding(.top, 4)
            }
            .padding(16)
            .background(Brand.tableDeep)
            .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(Brand.outline, lineWidth: Brand.stroke))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
    }
}

// MARK: - Tabs

/// The bottom bar. Three slabs; the live one is raised and gold. Replaces `TabView`, whose
/// bar is a blurred system material no amount of tinting makes ours.
struct CrashTabBar<Tab: Hashable>: View {
    let tabs: [(tab: Tab, glyph: PixelGlyph, title: String)]
    @Binding var selection: Tab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(tabs, id: \.tab) { entry in
                let on = entry.tab == selection
                Button {
                    guard !on else { return }
                    Haptics.knock()
                    selection = entry.tab
                } label: {
                    VStack(spacing: 5) {
                        PixelIcon(glyph: entry.glyph, size: 20,
                                  color: on ? Brand.outline : Brand.inkDim)
                        Text(entry.title)
                            .font(.brandCaption)
                            .foregroundStyle(on ? Brand.outline : Brand.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .slab(on ? Brand.gold : Brand.surface, radius: 11,
                          lift: on ? Brand.ledge : 2, highlight: on ? 0.22 : 0.06)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(entry.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(Motion.pop(reduceMotion), value: selection)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
