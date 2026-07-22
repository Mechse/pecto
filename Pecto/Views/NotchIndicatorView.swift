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
    /// Expanded, the wings also have to carry the card below them — a run row
    /// with a name, model, timer and a stop button needs the room.
    private static let expandedMinWingWidth: CGFloat = 230
    /// How far the bar extends below the notch strip.
    private static let bottomExtension: CGFloat = 10
    /// Width of the free-floating card on displays without a notch.
    private static let capsuleCardWidth: CGFloat = 460

    /// Wings share one width (the widest content, floored at the minimum) so
    /// the bar stays symmetric and the clear gap stays over the physical notch.
    private var wingWidth: CGFloat {
        max(
            controller.isExpanded ? Self.expandedMinWingWidth : Self.minWingWidth,
            leftWingWidth,
            rightWingWidth
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.state != .hidden {
                pill
                    // The shape's rect drives both the hover hot zone and the
                    // panel's hit region — everything outside it stays
                    // click-through over the menu bar.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        controller.shapeRectChanged($0)
                    }
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The panel overlaps the notch on purpose; the window's safe area
        // must not inset the content a second time.
        .ignoresSafeArea()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.state)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.isExpanded)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var pill: some View {
        let geometry = controller.geometry
        if geometry.hasNotch {
            // The wings draw over the menu bar (panel level is .statusBar);
            // the shape must be pure black to blend with the cutout. Expanded,
            // the same black grows downward into a card — one continuous
            // shape, as if the notch itself had opened.
            VStack(spacing: 0) {
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

                if controller.isExpanded {
                    expandedBody
                        .frame(width: wingWidth * 2 + geometry.notchWidth)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                Color.black,
                in: UnevenRoundedRectangle(
                    bottomLeadingRadius: controller.isExpanded ? 20 : 14,
                    bottomTrailingRadius: controller.isExpanded ? 20 : 14
                )
            )
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: controller.isExpanded ? 20 : 14,
                    bottomTrailingRadius: controller.isExpanded ? 20 : 14
                )
            )
        } else {
            VStack(spacing: 0) {
                inlineContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                if controller.isExpanded {
                    expandedBody
                        .frame(width: Self.capsuleCardWidth)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                .black.opacity(0.95),
                in: RoundedRectangle(cornerRadius: controller.isExpanded ? 18 : 999)
            )
            .clipShape(RoundedRectangle(cornerRadius: controller.isExpanded ? 18 : 999))
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

    // MARK: - Expanded card

    /// What the strip reveals when the cursor comes near: what's running and
    /// for how long, a way to stop it, and the last result to copy again.
    @ViewBuilder
    private var expandedBody: some View {
        let runs = controller.activeRuns
        VStack(alignment: .leading, spacing: 16) {
            Divider().overlay(Color.white.opacity(0.12))

            // The buttons live in the header, an inch above and already in
            // reach — repeating them here would just be two of everything.
            if isAwaitingConfirmation {
                section("Waiting on you") {
                    Text("This task reads your clipboard, but there's nothing on it. Run it anyway, or copy something and press the shortcut again.")
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !runs.isEmpty {
                section(runs.count == 1 ? "Running" : "Running (\(runs.count))") {
                    ForEach(runs, id: \.path) { run in
                        RunDetailRow(run: run) {
                            controller.cancelRun(path: run.path)
                        }
                    }
                }
            }

            if let output = controller.lastOutput {
                section(controller.lastOutputTaskName.map { "Last result — \($0)" } ?? "Last result") {
                    LastOutputSection(output: output) {
                        controller.copyLastOutput()
                    }
                }
            }

            if runs.isEmpty, controller.lastOutput == nil, !isAwaitingConfirmation {
                Text("Nothing running.")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(Self.pixelFont)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    /// A titled block. The title hugs its own content, so the gap between
    /// sections always reads wider than the gap inside one.
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            content()
        }
    }

    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = controller.state { return true }
        return false
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

/// One in-flight run in the expanded card: what it is, which model, how long
/// it's been going, and a way to stop it.
private struct RunDetailRow: View {
    let run: ActiveRun
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PixelEqualizer()
            VStack(alignment: .leading, spacing: 1) {
                Text(run.taskName)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(run.model.map(Self.shortModel) ?? "resolving model…")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Ticks a little faster than it displays, so the tenths never
            // visibly stall.
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(Self.elapsed(since: run.startedAt, now: context.date))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
            }
            Button {
                onCancel()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(NotchButtonStyle(prominent: false))
            .help("Stop this run")
        }
    }

    /// "anthropic:claude-sonnet-4-5" reads as its model name here — the card
    /// is narrow and the provider is implied by the name.
    private static func shortModel(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    private static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(start))
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

/// The last successful result: a few lines of it, and a way to put it back on
/// the clipboard — by the time you look, you may have copied something else.
private struct LastOutputSection: View {
    let output: String
    let onCopy: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(output)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(didCopy ? "Copied" : "Copy again") {
                    onCopy()
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        didCopy = false
                    }
                }
                .buttonStyle(NotchButtonStyle(prominent: !didCopy))
                Spacer(minLength: 0)
            }
        }
        // A new result resets the button even if the old label was still up.
        .onChange(of: output) { didCopy = false }
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
