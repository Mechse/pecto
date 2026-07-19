import SwiftUI

/// The indicator rendered on the notch panel. On a notched display it widens
/// the notch: a black bar spanning a wing on either side of the cutout, only
/// slightly taller than the notch itself. Content sits in the wings — status
/// on the left, overflow count on the right — never behind the physical
/// notch. Elsewhere it floats as a capsule just below the menu bar.
struct NotchIndicatorView: View {
    let controller: NotchIndicatorController

    @State private var leftWingWidth: CGFloat = 0
    @State private var rightWingWidth: CGFloat = 0

    /// Minimum wing on either side of the notch so the bar reads as a wide
    /// strip even when the status text is short.
    private static let minWingWidth: CGFloat = 150
    /// How far the bar extends below the notch strip.
    private static let bottomExtension: CGFloat = 10

    /// Wings share one width (the widest content, floored at the minimum) so
    /// the bar stays symmetric and the clear gap stays over the physical notch.
    private var wingWidth: CGFloat {
        max(Self.minWingWidth, leftWingWidth, rightWingWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.state != .hidden {
                pill
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The panel overlaps the notch on purpose; the window's safe area
        // must not inset the content a second time.
        .ignoresSafeArea()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.state)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var pill: some View {
        let geometry = controller.geometry
        if geometry.hasNotch {
            // The wings draw over the menu bar (panel level is .statusBar);
            // the shape must be pure black to blend with the cutout.
            HStack(spacing: 0) {
                leftContent
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leftWingWidth = $0 }
                    .frame(width: wingWidth, alignment: .leading)
                Color.clear
                    .frame(width: geometry.notchWidth)
                rightContent
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rightWingWidth = $0 }
                    .frame(width: wingWidth, alignment: .trailing)
            }
            .frame(height: geometry.topInset + Self.bottomExtension)
            .background(
                Color.black,
                in: UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
            )
        } else {
            inlineContent
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.95)))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .padding(.top, geometry.topInset + 6)
        }
    }

    // MARK: - Wing content (notched displays)

    private var leftContent: some View {
        HStack(spacing: 8) {
            switch controller.state {
            case .hidden:
                EmptyView()
            case .running(let primaryName, _):
                PixelEqualizer()
                Text("Running \(primaryName)")
                    .foregroundStyle(.white)
                    .lineLimit(1)
            case .awaitingConfirmation(let name):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(name): clipboard is empty")
                    .foregroundStyle(.white)
                    .lineLimit(1)
            case .flash(let kind, let message):
                Image(systemName: icon(for: kind))
                    .foregroundStyle(tint(for: kind))
                Text(message)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .font(Self.pixelFont)
        .padding(.leading, 18)
        .padding(.trailing, 12)
    }

    private var rightContent: some View {
        HStack(spacing: 8) {
            if case .running(_, let extraCount) = controller.state, extraCount > 0 {
                Text("+\(extraCount) more")
                    .foregroundStyle(.white.opacity(0.55))
            }
            if case .awaitingConfirmation = controller.state {
                confirmationButtons
            }
        }
        .font(Self.pixelFont)
        .padding(.leading, 12)
        .padding(.trailing, 18)
    }

    private var confirmationButtons: some View {
        HStack(spacing: 6) {
            Button("Run anyway") {
                controller.confirmPending()
            }
            .buttonStyle(NotchButtonStyle(prominent: true))
            Button {
                controller.cancelPending()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(NotchButtonStyle(prominent: false))
        }
    }

    // MARK: - Capsule content (displays without a notch)

    @ViewBuilder
    private var inlineContent: some View {
        HStack(spacing: 8) {
            switch controller.state {
            case .hidden:
                EmptyView()
            case .running(let primaryName, let extraCount):
                PixelEqualizer()
                Text("Running \(primaryName)")
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if extraCount > 0 {
                    Text("+\(extraCount) more")
                        .foregroundStyle(.white.opacity(0.55))
                }
            case .awaitingConfirmation(let name):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("\(name): clipboard is empty")
                    .foregroundStyle(.white)
                    .lineLimit(1)
                confirmationButtons
            case .flash(let kind, let message):
                Image(systemName: icon(for: kind))
                    .foregroundStyle(tint(for: kind))
                Text(message)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .font(Self.pixelFont)
    }

    private static let pixelFont: Font = .system(size: 11, weight: .medium, design: .monospaced)

    private func icon(for kind: RunOutcome.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .refusal: "exclamationmark.triangle.fill"
        }
    }

    private func tint(for kind: RunOutcome.Kind) -> Color {
        switch kind {
        case .success: .green
        case .failure: .red
        case .refusal: .yellow
        }
    }
}

/// Compact capsule buttons sized for the bar; default macOS button chrome
/// would clash with the pure-black notch look.
private struct NotchButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, prominent ? 8 : 5)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(prominent ? Color.yellow : Color.white.opacity(0.15))
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Retro equalizer: columns of square "pixels" whose heights step in a
/// pseudo-random dance. Deliberately unanimated between ticks — the abrupt
/// jumps are the pixel look.
private struct PixelEqualizer: View {
    private static let columns = 5
    private static let rows = 4
    private static let cell: CGFloat = 3
    private static let gap: CGFloat = 1
    private static let interval: TimeInterval = 0.16

    private static let barBlue = Color(red: 0.55, green: 0.72, blue: 1.0)
    private static let tipBlue = Color(red: 0.85, green: 0.91, blue: 1.0)

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.interval)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.interval)
            HStack(alignment: .bottom, spacing: Self.gap) {
                ForEach(0..<Self.columns, id: \.self) { column in
                    let filled = Self.barHeight(column: column, tick: tick)
                    VStack(spacing: Self.gap) {
                        ForEach(0..<Self.rows, id: \.self) { row in
                            let lit = row >= Self.rows - filled
                            Rectangle()
                                .fill(cellColor(row: row, filled: filled))
                                .frame(width: Self.cell, height: Self.cell)
                                .opacity(lit ? 1 : 0)
                        }
                    }
                }
            }
            .animation(nil, value: tick)
        }
        .frame(height: CGFloat(Self.rows) * Self.cell + CGFloat(Self.rows - 1) * Self.gap)
    }

    /// Filled cells (1...rows) for a column at a tick; xorshift keeps
    /// neighboring ticks/columns uncorrelated without any stored state.
    private static func barHeight(column: Int, tick: Int) -> Int {
        var x = UInt64(bitPattern: Int64(tick &+ column &* 7)) &+ 0x9E37_79B9_7F4A_7C15
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        return 1 + Int(x % UInt64(rows))
    }

    private func cellColor(row: Int, filled: Int) -> Color {
        row == Self.rows - filled ? Self.tipBlue : Self.barBlue
    }
}
