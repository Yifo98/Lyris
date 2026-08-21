import AppKit
import SwiftUI

enum LyrisTheme {
    static let grid: CGFloat = 24
    static let accent = Color(red: 0.62, green: 1.00, blue: 0.22)
    static let accentSoft = Color(red: 0.45, green: 0.86, blue: 0.14)
    static let background = Color(red: 0.012, green: 0.020, blue: 0.018)
    static let raisedBackground = Color(red: 0.025, green: 0.040, blue: 0.034)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.30)
    static let hairline = Color.white.opacity(0.12)
    static let cornerRadius: CGFloat = 28
}

struct LyrisGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

struct LyrisWindowDragRegion: View {
    @State private var initialWindowOrigin: NSPoint?

    var body: some View {
        LyrisNativeWindowDragRegion()
            .simultaneousGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                        if initialWindowOrigin == nil {
                            initialWindowOrigin = window.frame.origin
                        }
                        guard let initialWindowOrigin else { return }
                        window.setFrameOrigin(
                            NSPoint(
                                x: initialWindowOrigin.x + value.translation.width,
                                y: initialWindowOrigin.y - value.translation.height
                            )
                        )
                    }
                    .onEnded { _ in initialWindowOrigin = nil }
            )
    }
}

struct LyrisProgressiveText: View {
    let text: String
    let progress: Double
    let font: Font
    let baseColor: Color
    let progressColor: Color

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(baseColor)
            .overlay {
                Text(text)
                    .font(font)
                    .foregroundStyle(progressColor)
                    .mask {
                        GeometryReader { proxy in
                            Rectangle()
                                .frame(
                                    width: proxy.size.width * CGFloat(min(max(progress, 0), 1)),
                                    height: proxy.size.height
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
            }
            .accessibilityLabel(text)
    }
}

private struct LyrisMeasuredTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Keeps long lyric lines readable without relying on hover-only disclosure.
/// The text travels only when it overflows, and its offset follows the current
/// lyric line progress so the last words are visible before the next line.
struct LyrisSynchronizedMarqueeText: View {
    let text: String
    let progress: Double
    let font: Font
    let baseColor: Color
    let progressColor: Color
    var edgeFadeWidth: CGFloat = 0

    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let horizontalOffset = Self.horizontalOffset(
                contentWidth: contentWidth,
                containerWidth: proxy.size.width,
                progress: progress,
                contentInset: edgeFadeWidth
            )

            LyrisProgressiveText(
                text: text,
                progress: progress,
                font: font,
                baseColor: baseColor,
                progressColor: progressColor
            )
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { textProxy in
                    Color.clear.preference(
                        key: LyrisMeasuredTextWidthKey.self,
                        value: textProxy.size.width
                    )
                }
            }
            .offset(x: horizontalOffset)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .clipped()
        .mask {
            GeometryReader { proxy in
                let fadeFraction = min(
                    max(edgeFadeWidth / max(proxy.size.width, 1), 0),
                    0.5
                )
                if fadeFraction > 0 {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: fadeFraction),
                            .init(color: .white, location: 1 - fadeFraction),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Rectangle().fill(Color.white)
                }
            }
        }
        .onPreferenceChange(LyrisMeasuredTextWidthKey.self) { contentWidth = $0 }
        .accessibilityLabel(text)
    }

    static func travelProgress(for progress: Double) -> CGFloat {
        let normalized = min(max((progress - 0.12) / 0.76, 0), 1)
        // Smoothstep avoids an abrupt start or stop while remaining locked to
        // the lyric timeline instead of an independent marquee timer.
        return CGFloat(normalized * normalized * (3 - 2 * normalized))
    }

    static func horizontalOffset(
        contentWidth: CGFloat,
        containerWidth: CGFloat,
        progress: Double,
        contentInset: CGFloat = 0
    ) -> CGFloat {
        let protectedInset = min(
            max(contentInset, 0),
            max(containerWidth, 0) / 2
        )
        let protectedWidth = max(0, containerWidth - protectedInset * 2)
        let overflow = max(0, contentWidth - protectedWidth)
        guard overflow > 0 else {
            return protectedInset + max(0, protectedWidth - contentWidth) / 2
        }
        return protectedInset - overflow * travelProgress(for: progress)
    }
}

private struct LyrisNativeWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> LyrisWindowDragRegionView {
        LyrisWindowDragRegionView()
    }

    func updateNSView(_ nsView: LyrisWindowDragRegionView, context: Context) {}
}

final class LyrisWindowDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct LyrisGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let shadeOpacity: Double
    let skin: LyrisInterfaceSkin
    let content: Content

    init(
        cornerRadius: CGFloat = LyrisTheme.cornerRadius,
        shadeOpacity: Double = 0.72,
        skin: LyrisInterfaceSkin = .spotifyBlack,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.shadeOpacity = shadeOpacity
        self.skin = skin
        self.content = content()
    }

    var body: some View {
        ZStack {
            LyrisGlassBackground()
            skin.backgroundColor.opacity(shadeOpacity)
            LinearGradient(
                colors: [
                    skin.accentColor.opacity(0.055),
                    .clear,
                    Color.black.opacity(0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(LyrisTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 30, y: 14)
    }
}

enum LyrisWaveformModel {
    static func heights(count: Int, seed: String) -> [Double] {
        guard count > 0 else { return [] }
        var state = stableSeed(seed)
        return (0..<count).map { index in
            state = state &* 6_364_136_223_846_793_005
                &+ 1_442_695_040_888_963_407
            let random = Double((state >> 11) & ((1 << 53) - 1))
                / Double(1 << 53)
            let wave = 0.5 + 0.5 * sin(Double(index) * 0.64 + Double(state % 97) / 21)
            return min(max(0.18 + random * 0.52 + wave * 0.30, 0.12), 1)
        }
    }

    private static func stableSeed(_ value: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 0x9E37_79B9_7F4A_7C15 : hash
    }
}

struct LyrisFlowThread: Equatable {
    let baseline: CGFloat
    let amplitude: CGFloat
    let secondaryAmplitude: CGFloat
    let frequency: Double
    let secondaryFrequency: Double
    let phaseOffset: Double
    let speed: Double
    let lineWidth: CGFloat
    let opacity: Double
    let colorMix: Double
    let isDotted: Bool
}

enum LyrisFlowThreadModel {
    static func threads(count: Int, seed: String) -> [LyrisFlowThread] {
        guard count > 0 else { return [] }
        var state = stableSeed(seed)
        return (0..<count).map { index in
            let baseline = CGFloat(0.62 + nextUnit(&state) * 0.22)
            let amplitude = CGFloat(0.026 + nextUnit(&state) * 0.040)
            let secondaryAmplitude = CGFloat(0.008 + nextUnit(&state) * 0.014)
            let frequency = 0.70 + nextUnit(&state) * 0.95
            let secondaryFrequency = 0.42 + nextUnit(&state) * 0.86
            let phaseOffset = nextUnit(&state) * .pi * 2
            let speed = 0.34 + nextUnit(&state) * 0.56
            let lineWidth = CGFloat(0.50 + nextUnit(&state) * 0.36)
            let opacity = 0.28 + nextUnit(&state) * 0.34
            let colorMix = nextUnit(&state)
            return LyrisFlowThread(
                baseline: baseline,
                amplitude: amplitude,
                secondaryAmplitude: secondaryAmplitude,
                frequency: frequency,
                secondaryFrequency: secondaryFrequency,
                phaseOffset: phaseOffset,
                speed: speed,
                lineWidth: lineWidth,
                opacity: opacity,
                colorMix: colorMix,
                isDotted: index % 5 == 3
            )
        }
    }

    static func normalizedY(
        for thread: LyrisFlowThread,
        normalizedX: CGFloat,
        phase: TimeInterval
    ) -> CGFloat {
        let x = Double(min(max(normalizedX, 0), 1))
        let primary = sin(
            x * thread.frequency * .pi * 2
                + phase * thread.speed
                + thread.phaseOffset
        )
        let secondary = cos(
            x * thread.secondaryFrequency * .pi * 2
                - phase * thread.speed * 0.67
                + thread.phaseOffset * 0.43
        )
        let ambientSway = sin(phase * 0.11 + thread.phaseOffset * 1.7) * 0.008
        let y = thread.baseline
            + CGFloat(primary) * thread.amplitude
            + CGFloat(secondary) * thread.secondaryAmplitude
            + CGFloat(ambientSway)
        return min(max(y, 0), 1)
    }

    private static func stableSeed(_ value: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 0xA24B_AED4_963E_E407 : hash
    }

    private static func nextUnit(_ state: inout UInt64) -> Double {
        state = state &* 6_364_136_223_846_793_005
            &+ 1_442_695_040_888_963_407
        return Double((state >> 11) & ((1 << 53) - 1)) / Double(1 << 53)
    }
}

enum LyrisFlowComposition: Equatable {
    case interwoven
    case orbitalBreathing
    case counterpoint
}

struct LyrisOrbitalRing: Equatable {
    let horizontalInset: CGFloat
    let centerY: CGFloat
    let height: CGFloat
    let lineWidth: CGFloat
    let opacity: Double
    let phaseOffset: Double
    let speed: Double
    let colorMix: Double
    let isPrimary: Bool
}

enum LyrisOrbitalRingModel {
    static func rings(seed: String) -> [LyrisOrbitalRing] {
        let variations = LyrisWaveformModel.heights(count: 6, seed: "\(seed)-orbital")
        let presets: [(
            inset: CGFloat,
            centerY: CGFloat,
            height: CGFloat,
            width: CGFloat,
            opacity: Double,
            speed: Double,
            primary: Bool
        )] = [
            (0.25, 0.69, 0.22, 0.92, 0.76, 0.34, true),
            (0.20, 0.69, 0.32, 0.72, 0.58, 0.28, true),
            (0.16, 0.69, 0.40, 0.48, 0.25, 0.23, false),
            (0.29, 0.69, 0.16, 0.46, 0.28, 0.41, false),
            (0.13, 0.69, 0.44, 0.38, 0.16, 0.19, false),
            (0.33, 0.69, 0.11, 0.36, 0.14, 0.47, false),
        ]
        return presets.indices.map { index in
            let variation = variations[index]
            let preset = presets[index]
            return LyrisOrbitalRing(
                horizontalInset: preset.inset,
                centerY: preset.centerY,
                height: preset.height,
                lineWidth: preset.width,
                opacity: preset.opacity,
                phaseOffset: variation * .pi * 2,
                speed: preset.speed,
                colorMix: min(max(variation, 0), 1),
                isPrimary: preset.primary
            )
        }
    }

    static func normalizedRect(
        for ring: LyrisOrbitalRing,
        phase: TimeInterval
    ) -> CGRect {
        let breath = CGFloat(sin(phase * ring.speed + ring.phaseOffset))
        let drift = CGFloat(cos(phase * ring.speed * 0.73 + ring.phaseOffset))
        let width = min(
            max(1 - ring.horizontalInset * 2 + breath * 0.016, 0.08),
            0.92
        )
        let height = ring.height * (1 + breath * 0.06)
        let centerY = ring.centerY + drift * 0.006
        return CGRect(
            x: (1 - width) / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}

enum LyrisExpandedIslandEffectPolicy {
    static let composition: LyrisFlowComposition = .counterpoint
    static let opacity = 0.50
    static let motionMultiplier = 2.8
    static let framesPerSecond = 30
}

struct LyrisCounterpointVoice: Equatable {
    let direction: CGFloat
    let verticalOffset: CGFloat
    let phaseOffset: Double
    let speed: Double
    let lineWidth: CGFloat
    let opacity: Double
    let colorMix: Double
    let isPrimary: Bool
    let isDotted: Bool
}

enum LyrisCounterpointModel {
    static func voices(seed: String) -> [LyrisCounterpointVoice] {
        let variations = LyrisWaveformModel.heights(
            count: 8,
            seed: "\(seed)-counterpoint"
        )
        let echoOffsets: [CGFloat] = [-0.052, -0.025, 0.042]
        var voices: [LyrisCounterpointVoice] = [
            LyrisCounterpointVoice(
                direction: 1,
                verticalOffset: 0,
                phaseOffset: variations[0] * .pi * 2,
                speed: 0.92 + variations[0] * 0.34,
                lineWidth: 1.34,
                opacity: 0.96,
                colorMix: 0,
                isPrimary: true,
                isDotted: false
            ),
            LyrisCounterpointVoice(
                direction: -1,
                verticalOffset: 0,
                phaseOffset: variations[0] * .pi * 2,
                speed: 0.92 + variations[0] * 0.34,
                lineWidth: 1.22,
                opacity: 0.96,
                colorMix: 1,
                isPrimary: true,
                isDotted: false
            ),
        ]
        for index in echoOffsets.indices {
            let variation = variations[index + 2]
            voices.append(
                LyrisCounterpointVoice(
                    direction: 1,
                    verticalOffset: echoOffsets[index],
                    phaseOffset: variation * .pi * 2,
                    speed: 0.72 + variation * 0.38,
                    lineWidth: 0.54,
                    opacity: 0.28 + variation * 0.12,
                    colorMix: 0.18,
                    isPrimary: false,
                    isDotted: index == 1
                )
            )
        }
        for index in echoOffsets.indices {
            let variation = variations[index + 5]
            voices.append(
                LyrisCounterpointVoice(
                    direction: -1,
                    verticalOffset: -echoOffsets[index],
                    phaseOffset: variation * .pi * 2,
                    speed: 0.74 + variation * 0.40,
                    lineWidth: 0.52,
                    opacity: 0.27 + variation * 0.12,
                    colorMix: 0.82,
                    isPrimary: false,
                    isDotted: index == 0 || index == 2
                )
            )
        }
        return voices
    }

    static func travelPhase(
        for voice: LyrisCounterpointVoice,
        phase: TimeInterval
    ) -> Double {
        phase * voice.speed * Double(voice.direction)
    }

    static func normalizedY(
        for voice: LyrisCounterpointVoice,
        normalizedX: CGFloat,
        crossingX: CGFloat,
        phase: TimeInterval
    ) -> CGFloat {
        let x = min(max(normalizedX, 0), 1)
        let crossing = min(max(crossingX, 0.32), 0.76)
        let spatial = Double(x - crossing)
        let travel = travelPhase(for: voice, phase: phase)
        let spatialFrequency = 1.18 + voice.speed * 0.34
        let primaryCurve = CGFloat(
            sin(
                spatial * .pi * 2 * spatialFrequency
                    + travel
                    + voice.phaseOffset
            )
        ) * 0.078
        let secondaryCurve = CGFloat(
            sin(
                spatial * .pi * 2 * (spatialFrequency * 2.08)
                    - travel * 0.58
                    + voice.phaseOffset * 0.47
            )
        ) * 0.034
        let commonBreath = CGFloat(sin(phase * 1.24)) * 0.014
        let y = 0.68
            + voice.verticalOffset
            + voice.direction * (primaryCurve + secondaryCurve)
            + commonBreath
        return min(max(y, 0), 1)
    }
}

enum LyrisCounterpointDissolveModel {
    static let particleCount = 64

    static func normalizedPosition(
        for particle: LyrisAmbientParticle,
        index: Int,
        voices: [LyrisCounterpointVoice],
        crossingX: CGFloat,
        phase: TimeInterval
    ) -> CGPoint {
        let edgePosition = LyrisFlowEdgeDissolveModel.normalizedPosition(
            for: particle,
            index: index,
            phase: phase
        )
        guard !voices.isEmpty else { return edgePosition }
        let primaryCount = min(2, voices.count)
        let voice = voices[(index / 2) % primaryCount]
        let curveY = LyrisCounterpointModel.normalizedY(
            for: voice,
            normalizedX: edgePosition.x,
            crossingX: crossingX,
            phase: phase
        )
        let scatter = (particle.baseY - 0.5) * 0.14
            + CGFloat(
                sin(phase * 0.92 + particle.phaseOffset)
            ) * 0.018
        return CGPoint(
            x: edgePosition.x,
            y: min(max(curveY + scatter, 0.48), 0.92)
        )
    }
}

enum LyrisCounterpointRenderRegion: Equatable {
    case continuousLine
    case fragmentedLine
    case particlesOnly
}

enum LyrisCounterpointFragmentTexture: CaseIterable {
    case coarse
    case medium
    case fine
}

enum LyrisCounterpointDissolvePolicy {
    static let leadingBoundary: CGFloat = 0.25
    static let trailingBoundary: CGFloat = 0.78
    static let fragmentSpan: CGFloat = 0.11
    static let blendSamples: [CGFloat] = [
        0,
        0.08,
        0.18,
        0.32,
        0.50,
        0.68,
        0.84,
        1,
    ]

    static func region(at normalizedX: CGFloat) -> LyrisCounterpointRenderRegion {
        let x = min(max(normalizedX, 0), 1)
        if x < leadingBoundary - fragmentSpan
            || x > trailingBoundary + fragmentSpan {
            return .particlesOnly
        }
        if x < leadingBoundary || x > trailingBoundary {
            return .fragmentedLine
        }
        return .continuousLine
    }

    static func fragmentOpacity(
        for texture: LyrisCounterpointFragmentTexture,
        progress: CGFloat
    ) -> Double {
        let progress = min(max(progress, 0), 1)
        switch texture {
        case .coarse:
            return smoothstep(from: 0.42, to: 0.94, value: progress)
        case .medium:
            return smoothstep(from: 0.10, to: 0.54, value: progress)
                * (1 - smoothstep(from: 0.70, to: 0.98, value: progress))
                * 0.78
        case .fine:
            return smoothstep(from: 0, to: 0.18, value: progress)
                * (1 - smoothstep(from: 0.48, to: 0.84, value: progress))
                * 0.62
        }
    }

    private static func smoothstep(
        from lowerBound: CGFloat,
        to upperBound: CGFloat,
        value: CGFloat
    ) -> Double {
        guard upperBound > lowerBound else {
            return value >= upperBound ? 1 : 0
        }
        let normalized = min(
            max((value - lowerBound) / (upperBound - lowerBound), 0),
            1
        )
        return Double(normalized * normalized * (3 - 2 * normalized))
    }
}

enum LyrisFlowThreadRenderPolicy {
    static let threadCount = 12
    static let framesPerSecond = 24
    static let renderSurfaceCount = 1
    static let minimumSampleCount = 32
    static let maximumSampleCount = 48
    static let maximumPointCountPerFrame = threadCount * maximumSampleCount

    static func sampleCount(for width: CGFloat) -> Int {
        max(minimumSampleCount, min(maximumSampleCount, Int(width / 14)))
    }
}

private struct LyrisFlowThreadField: View {
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin
    let profile: LyrisLinkedEffectProfile
    let phase: TimeInterval
    let pulse: Double
    let seed: String

    var body: some View {
        let threads = LyrisFlowThreadModel.threads(
            count: LyrisFlowThreadRenderPolicy.threadCount,
            seed: "\(seed)-flow-threads"
        )
        Canvas(
            opaque: false,
            colorMode: .linear,
            rendersAsynchronously: true
        ) { context, size in
            let sampleCount = LyrisFlowThreadRenderPolicy.sampleCount(
                for: size.width
            )
            for index in threads.indices {
                let thread = threads[index]
                let firstColor = thread.colorMix < 0.5
                    ? skin.accentColor
                    : skin.secondaryAccentColor
                let secondColor = thread.colorMix < 0.5
                    ? skin.secondaryAccentColor
                    : skin.accentColor
                let intensity = min(
                    0.86,
                    thread.opacity + profile.borderIntensity * 0.12
                ) * pulse
                let amplitudeScale: CGFloat = style == .pulse ? 1.18 : 1
                var path = Path()
                for sample in 0...sampleCount {
                    let normalizedX = CGFloat(sample) / CGFloat(sampleCount)
                    let baseY = LyrisFlowThreadModel.normalizedY(
                        for: thread,
                        normalizedX: normalizedX,
                        phase: phase * profile.animationRate
                    )
                    let shapedY = thread.baseline
                        + (baseY - thread.baseline) * amplitudeScale
                    let point = CGPoint(
                        x: normalizedX * size.width,
                        y: shapedY * size.height
                    )
                    if sample == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }

                if index.isMultiple(of: 4) {
                    context.stroke(
                        path,
                        with: .color(firstColor.opacity(intensity * 0.16)),
                        lineWidth: thread.lineWidth + 1.2
                    )
                }
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(
                                color: firstColor.opacity(intensity * 0.18),
                                location: 0.10
                            ),
                            .init(
                                color: firstColor.opacity(intensity * 0.74),
                                location: 0.24
                            ),
                            .init(
                                color: firstColor.opacity(intensity),
                                location: 0.40
                            ),
                            .init(
                                color: secondColor.opacity(intensity * 0.95),
                                location: 0.60
                            ),
                            .init(
                                color: secondColor.opacity(intensity * 0.68),
                                location: 0.76
                            ),
                            .init(
                                color: secondColor.opacity(intensity * 0.16),
                                location: 0.90
                            ),
                            .init(color: .clear, location: 1),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(
                        lineWidth: thread.lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: thread.isDotted ? [1.0, 5.2] : [],
                        dashPhase: thread.isDotted
                            ? CGFloat(-phase * profile.animationRate * 7.5)
                            : 0
                    )
                )
            }

            let edgeParticles = LyrisAmbientParticleModel.particles(
                count: LyrisFlowEdgeDissolveModel.particleCount,
                seed: "\(seed)-edge-dissolve"
            )
            for index in edgeParticles.indices {
                let particle = edgeParticles[index]
                let position = LyrisFlowEdgeDissolveModel.normalizedPosition(
                    for: particle,
                    index: index,
                    phase: phase * profile.animationRate
                )
                let edgeDistance = min(position.x, 1 - position.x)
                let transition = min(max((0.24 - edgeDistance) / 0.20, 0), 1)
                let color = particle.colorMix < 0.5
                    ? skin.accentColor
                    : skin.secondaryAccentColor
                let radius = particle.radius * (0.70 + transition * 0.92)
                let center = CGPoint(
                    x: position.x * size.width,
                    y: position.y * size.height
                )
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    ),
                    with: .color(
                        color.opacity(
                            particle.opacity
                                * (0.42 + Double(transition) * 1.18)
                                * pulse
                        )
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct LyrisOrbitalBreathingField: View {
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin
    let profile: LyrisLinkedEffectProfile
    let phase: TimeInterval
    let pulse: Double
    let seed: String

    var body: some View {
        let rings = LyrisOrbitalRingModel.rings(seed: seed)
        Canvas(
            opaque: false,
            colorMode: .linear,
            rendersAsynchronously: true
        ) { context, size in
            for index in rings.indices {
                let ring = rings[index]
                let normalized = LyrisOrbitalRingModel.normalizedRect(
                    for: ring,
                    phase: phase * profile.animationRate
                )
                let rect = CGRect(
                    x: normalized.minX * size.width,
                    y: normalized.minY * size.height,
                    width: normalized.width * size.width,
                    height: normalized.height * size.height
                )
                let path = Path(ellipseIn: rect)
                let firstColor = ring.colorMix < 0.52
                    ? skin.accentColor
                    : skin.secondaryAccentColor
                let secondColor = ring.colorMix < 0.52
                    ? skin.secondaryAccentColor
                    : skin.accentColor
                let intensity = ring.opacity
                    * (style == .pulse ? pulse : 1)

                if ring.isPrimary {
                    context.stroke(
                        path,
                        with: .color(firstColor.opacity(intensity * 0.13)),
                        lineWidth: ring.lineWidth + 1.8
                    )
                }
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(
                                color: firstColor.opacity(intensity * 0.18),
                                location: 0.10
                            ),
                            .init(
                                color: firstColor.opacity(intensity * 0.88),
                                location: 0.25
                            ),
                            .init(
                                color: firstColor.opacity(intensity),
                                location: 0.42
                            ),
                            .init(
                                color: secondColor.opacity(intensity * 0.92),
                                location: 0.62
                            ),
                            .init(
                                color: secondColor.opacity(intensity * 0.72),
                                location: 0.78
                            ),
                            .init(
                                color: secondColor.opacity(intensity * 0.14),
                                location: 0.91
                            ),
                            .init(color: .clear, location: 1),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(
                        lineWidth: ring.lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: !ring.isPrimary && index.isMultiple(of: 2)
                            ? [1.0, 6.0]
                            : [],
                        dashPhase: CGFloat(-phase * ring.speed * 6.5)
                    )
                )
            }

            let edgeParticles = LyrisAmbientParticleModel.particles(
                count: LyrisFlowEdgeDissolveModel.particleCount,
                seed: "\(seed)-orbital-edge"
            )
            for index in edgeParticles.indices {
                let particle = edgeParticles[index]
                let position = LyrisFlowEdgeDissolveModel.normalizedPosition(
                    for: particle,
                    index: index,
                    phase: phase * profile.animationRate
                )
                let edgeDistance = min(position.x, 1 - position.x)
                let transition = min(max((0.24 - edgeDistance) / 0.20, 0), 1)
                let color = particle.colorMix < 0.5
                    ? skin.accentColor
                    : skin.secondaryAccentColor
                let radius = particle.radius * (0.78 + transition * 1.02)
                let center = CGPoint(
                    x: position.x * size.width,
                    y: position.y * size.height
                )
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    ),
                    with: .color(
                        color.opacity(
                            particle.opacity
                                * (0.44 + Double(transition) * 1.20)
                                * pulse
                        )
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct LyrisCounterpointField: View {
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin
    let profile: LyrisLinkedEffectProfile
    let phase: TimeInterval
    let pulse: Double
    let progress: Double
    let seed: String

    var body: some View {
        let voices = LyrisCounterpointModel.voices(seed: seed)
        Canvas(
            opaque: false,
            colorMode: .linear,
            rendersAsynchronously: true
        ) { context, size in
            let sampleCount = LyrisFlowThreadRenderPolicy.sampleCount(
                for: size.width
            )
            let counterpointColor: Color
            switch skin {
            case .spotifyBlack:
                counterpointColor = Color(red: 0.10, green: 0.86, blue: 0.72)
            case .midnightAurora:
                counterpointColor = Color(red: 0.18, green: 0.82, blue: 1.00)
            case .graphite:
                counterpointColor = Color(red: 0.52, green: 0.72, blue: 0.78)
            }
            let crossingX = CGFloat(min(max(progress, 0.32), 0.76))
            let motionPhase = phase
                * profile.animationRate
                * LyrisExpandedIslandEffectPolicy.motionMultiplier
            for index in voices.indices {
                let voice = voices[index]
                let voiceColor = voice.colorMix < 0.5
                    ? skin.accentColor
                    : counterpointColor
                let intensity = voice.opacity
                    * (style == .pulse ? pulse : 1)
                func curvePath(
                    from lowerBound: CGFloat,
                    to upperBound: CGFloat
                ) -> Path {
                    let segmentCount = max(
                        5,
                        Int(
                            ceil(
                                CGFloat(sampleCount)
                                    * max(upperBound - lowerBound, 0.01)
                            )
                        )
                    )
                    var path = Path()
                    for segment in 0...segmentCount {
                        let fraction = CGFloat(segment) / CGFloat(segmentCount)
                        let normalizedX = lowerBound
                            + (upperBound - lowerBound) * fraction
                        let y = LyrisCounterpointModel.normalizedY(
                            for: voice,
                            normalizedX: normalizedX,
                            crossingX: crossingX,
                            phase: motionPhase
                        )
                        let point = CGPoint(
                            x: normalizedX * size.width,
                            y: y * size.height
                        )
                        if segment == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    return path
                }
                let centerPath = curvePath(
                    from: LyrisCounterpointDissolvePolicy.leadingBoundary,
                    to: LyrisCounterpointDissolvePolicy.trailingBoundary
                )
                let leftFragmentPath = curvePath(
                    from: LyrisCounterpointDissolvePolicy.leadingBoundary
                        - LyrisCounterpointDissolvePolicy.fragmentSpan,
                    to: LyrisCounterpointDissolvePolicy.leadingBoundary
                )
                let rightFragmentPath = curvePath(
                    from: LyrisCounterpointDissolvePolicy.trailingBoundary,
                    to: LyrisCounterpointDissolvePolicy.trailingBoundary
                        + LyrisCounterpointDissolvePolicy.fragmentSpan
                )

                func fragmentGradientStops(
                    for texture: LyrisCounterpointFragmentTexture,
                    isLeading: Bool
                ) -> [Gradient.Stop] {
                    LyrisCounterpointDissolvePolicy.blendSamples.map { progress in
                        let location: CGFloat
                        if isLeading {
                            location = LyrisCounterpointDissolvePolicy.leadingBoundary
                                - LyrisCounterpointDissolvePolicy.fragmentSpan
                                + LyrisCounterpointDissolvePolicy.fragmentSpan * progress
                        } else {
                            location = LyrisCounterpointDissolvePolicy.trailingBoundary
                                + LyrisCounterpointDissolvePolicy.fragmentSpan
                                    * (1 - progress)
                        }
                        return Gradient.Stop(
                            color: voiceColor.opacity(
                                intensity
                                    * LyrisCounterpointDissolvePolicy.fragmentOpacity(
                                        for: texture,
                                        progress: progress
                                    )
                            ),
                            location: Double(location)
                        )
                    }
                    .sorted { $0.location < $1.location }
                }

                if voice.isPrimary {
                    context.stroke(
                        centerPath,
                        with: .color(voiceColor.opacity(intensity * 0.24)),
                        lineWidth: voice.lineWidth + 2.8
                    )
                }
                context.stroke(
                    centerPath,
                    with: .color(voiceColor.opacity(intensity)),
                    style: StrokeStyle(
                        lineWidth: voice.lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: voice.isDotted ? [1.0, 5.0] : [],
                        dashPhase: CGFloat(-motionPhase * voice.speed * 8.5)
                    )
                )
                let fragmentLayers: [(
                    texture: LyrisCounterpointFragmentTexture,
                    widthScale: CGFloat,
                    dash: [CGFloat],
                    phaseScale: Double
                )] = [
                    (.coarse, 0.92, [9.0, 1.8], 8.8),
                    (.medium, 0.74, [3.8, 2.6], 10.2),
                    (.fine, 0.56, [1.0, 3.7], 11.8),
                ]
                for layer in fragmentLayers {
                    let strokeStyle = StrokeStyle(
                        lineWidth: voice.lineWidth * layer.widthScale,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: layer.dash,
                        dashPhase: CGFloat(
                            -motionPhase * voice.speed * layer.phaseScale
                        )
                    )
                    context.stroke(
                        leftFragmentPath,
                        with: .linearGradient(
                            Gradient(
                                stops: fragmentGradientStops(
                                    for: layer.texture,
                                    isLeading: true
                                )
                            ),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        style: strokeStyle
                    )
                    context.stroke(
                        rightFragmentPath,
                        with: .linearGradient(
                            Gradient(
                                stops: fragmentGradientStops(
                                    for: layer.texture,
                                    isLeading: false
                                )
                            ),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        style: strokeStyle
                    )
                }
            }

            let edgeParticles = LyrisAmbientParticleModel.particles(
                count: LyrisCounterpointDissolveModel.particleCount,
                seed: "\(seed)-counterpoint-edge"
            )
            for index in edgeParticles.indices {
                let particle = edgeParticles[index]
                let position = LyrisCounterpointDissolveModel.normalizedPosition(
                    for: particle,
                    index: index,
                    voices: voices,
                    crossingX: crossingX,
                    phase: motionPhase
                )
                let isLeft = position.x < 0.5
                let boundary = isLeft
                    ? LyrisCounterpointDissolvePolicy.leadingBoundary
                    : LyrisCounterpointDissolvePolicy.trailingBoundary
                let availableSpan = isLeft ? boundary : 1 - boundary
                let distanceFromBoundary = abs(position.x - boundary)
                let dissolveProgress = min(
                    max(distanceFromBoundary / max(availableSpan, 0.001), 0),
                    1
                )
                let voiceIndex = (index / 2) % min(2, voices.count)
                let color = voices[voiceIndex].colorMix < 0.5
                    ? skin.accentColor
                    : counterpointColor
                let radius = particle.radius * (0.90 - dissolveProgress * 0.54)
                let center = CGPoint(
                    x: position.x * size.width,
                    y: position.y * size.height
                )
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: center.x - radius,
                            y: center.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                    ),
                    with: .color(
                        color.opacity(
                            particle.opacity
                                * (0.96 - Double(dissolveProgress) * 0.72)
                                * pulse
                        )
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

struct LyrisGlobalFlowThreadOverlay: View {
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin
    let isPlaying: Bool
    var isActive = true
    var framesPerSecond: Double?
    var seed: String = "lyris-global-flow"
    var composition: LyrisFlowComposition = .interwoven
    var progress: Double = 0.5

    var body: some View {
        let resolvedStyle = style.normalized
        TimelineView(
            .animation(
                minimumInterval: 1 / Double(
                    max(
                        framesPerSecond
                            ?? Double(
                                composition == .counterpoint
                                    ? LyrisExpandedIslandEffectPolicy.framesPerSecond
                                    : LyrisFlowThreadRenderPolicy.framesPerSecond
                            ),
                        1
                    )
                ),
                paused: LyrisLinkedEffectMotionPolicy.timelineIsPaused(
                    style: resolvedStyle,
                    isActive: isActive
                )
            )
        ) { timeline in
            if resolvedStyle.profile.isEnabled {
                let phase = timeline.date.timeIntervalSinceReferenceDate
                    * LyrisLinkedEffectMotionPolicy.phaseScale(
                        isPlaying: isPlaying
                    )
                let pulse = resolvedStyle == .pulse
                    ? 0.78 + 0.22 * sin(
                        phase * resolvedStyle.profile.animationRate * 2.1
                    )
                    : 1.0
                switch composition {
                case .interwoven:
                    LyrisFlowThreadField(
                        style: resolvedStyle,
                        skin: skin,
                        profile: resolvedStyle.profile,
                        phase: phase,
                        pulse: pulse,
                        seed: seed
                    )
                case .orbitalBreathing:
                    LyrisOrbitalBreathingField(
                        style: resolvedStyle,
                        skin: skin,
                        profile: resolvedStyle.profile,
                        phase: phase,
                        pulse: pulse,
                        seed: seed
                    )
                case .counterpoint:
                    LyrisCounterpointField(
                        style: resolvedStyle,
                        skin: skin,
                        profile: resolvedStyle.profile,
                        phase: phase,
                        pulse: pulse,
                        progress: progress,
                        seed: seed
                    )
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LyrisAmbientParticle: Equatable {
    let baseX: CGFloat
    let baseY: CGFloat
    let radius: CGFloat
    let opacity: Double
    let phaseOffset: Double
    let speed: Double
    let verticalDrift: CGFloat
    let colorMix: Double
}

enum LyrisAmbientParticleModel {
    static func particles(count: Int, seed: String) -> [LyrisAmbientParticle] {
        guard count > 0 else { return [] }
        var state = stableSeed(seed)
        return (0..<count).map { _ in
            let baseX = CGFloat(nextUnit(&state))
            // Keep most particles close to the lyric stage while allowing a
            // quiet tail across metadata and transport surfaces.
            let rawY = nextUnit(&state)
            let baseY = CGFloat(0.14 + rawY * 0.72)
            let radius = CGFloat(0.45 + nextUnit(&state) * 1.35)
            let opacity = 0.055 + nextUnit(&state) * 0.245
            let phaseOffset = nextUnit(&state) * .pi * 2
            let speed = 0.06 + nextUnit(&state) * 0.16
            let verticalDrift = CGFloat(0.006 + nextUnit(&state) * 0.026)
            let colorMix = nextUnit(&state)
            return LyrisAmbientParticle(
                baseX: baseX,
                baseY: baseY,
                radius: radius,
                opacity: opacity,
                phaseOffset: phaseOffset,
                speed: speed,
                verticalDrift: verticalDrift,
                colorMix: colorMix
            )
        }
    }

    static func normalizedPosition(
        for particle: LyrisAmbientParticle,
        phase: TimeInterval
    ) -> CGPoint {
        let travel = particle.baseX + CGFloat(phase * particle.speed * 0.10)
        let wrappedX = travel - floor(travel)
        let y = particle.baseY
            + CGFloat(
                sin(
                    phase * (0.55 + particle.speed * 2.6)
                        + particle.phaseOffset
                )
            )
                * particle.verticalDrift
        return CGPoint(x: wrappedX, y: min(max(y, 0), 1))
    }

    private static func stableSeed(_ value: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash == 0 ? 0xD1B5_4A32_D192_ED03 : hash
    }

    private static func nextUnit(_ state: inout UInt64) -> Double {
        state = state &* 6_364_136_223_846_793_005
            &+ 1_442_695_040_888_963_407
        return Double((state >> 11) & ((1 << 53) - 1)) / Double(1 << 53)
    }
}

enum LyrisFlowEdgeDissolveModel {
    static let particleCount = 32

    static func normalizedPosition(
        for particle: LyrisAmbientParticle,
        index: Int,
        phase: TimeInterval
    ) -> CGPoint {
        let isLeft = index.isMultiple(of: 2)
        let baseDepth = 0.025 + particle.baseX * 0.19
        let horizontalDrift = CGFloat(
            sin(phase * (0.32 + particle.speed) + particle.phaseOffset)
        ) * 0.010
        let x = isLeft
            ? baseDepth + horizontalDrift
            : 1 - baseDepth - horizontalDrift
        let normalizedParticleY = (particle.baseY - 0.14) / 0.72
        let y = 0.58
            + normalizedParticleY * 0.28
            + CGFloat(
                sin(phase * 0.46 + particle.phaseOffset * 0.73)
            ) * min(particle.verticalDrift, 0.018)
        return CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

enum LyrisAmbientParticleRenderPolicy {
    static let framesPerSecond = 24
    static let minimumCount = 36
    static let maximumCount = 90

    static func count(for width: CGFloat) -> Int {
        max(minimumCount, min(maximumCount, Int(width / 10)))
    }
}

struct LyrisWaveformView: View {
    let trackID: String
    let progress: Double
    let isPlaying: Bool
    var isActive = true
    var accentColor: Color = LyrisTheme.accent

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 18,
                paused: !isActive || !isPlaying
            )
        ) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let count = max(10, min(84, Int(proxy.size.width / 3.2)))
                let heights = LyrisWaveformModel.heights(count: count, seed: trackID)
                let spacing = max(
                    0.7,
                    min(1.6, proxy.size.width / CGFloat(max(count * 3, 1)))
                )
                let barWidth = max(
                    0.8,
                    min(
                        1.6,
                        (proxy.size.width - spacing * CGFloat(max(count - 1, 0)))
                            / CGFloat(max(count, 1))
                    )
                )
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(heights.indices, id: \.self) { index in
                        let normalized = Double(index) / Double(max(heights.count - 1, 1))
                        let elapsed = normalized <= progress
                        let motion = isPlaying
                            ? 0.70 + 0.30 * abs(sin(phase * 3.1 + Double(index) * 0.72))
                            : 0.72
                        Capsule()
                            .fill(elapsed ? accentColor : accentColor.opacity(0.18))
                            .frame(
                                width: barWidth,
                                height: max(2, proxy.size.height * CGFloat(heights[index] * motion))
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

struct LyrisSoftDivider: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, Color.white.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .accessibilityHidden(true)
    }
}

struct LyrisTopPlayerMaterialProfile: Equatable {
    let usesHardwareBlack: Bool
    let skinTintOpacity: Double
    let linkedEffectOpacity: Double
    let edgeLightOpacity: Double

    static func resolve(for state: LyrisIslandState) -> Self {
        switch state {
        case .compact:
            Self(
                usesHardwareBlack: true,
                skinTintOpacity: 0,
                linkedEffectOpacity: 0,
                edgeLightOpacity: 0
            )
        case .expanded:
            Self(
                usesHardwareBlack: false,
                skinTintOpacity: 0.055,
                linkedEffectOpacity: 0.88,
                edgeLightOpacity: 0.14
            )
        }
    }
}

struct LyrisSettingsMaterialProfile: Equatable {
    let effectOpacity: Double
    let animates: Bool

    static func resolve(style: LinkedEffectStyle) -> Self {
        switch style.normalized {
        case .aurora:
            Self(effectOpacity: 0.56, animates: true)
        case .pulse:
            Self(effectOpacity: 0.72, animates: true)
        case .off:
            Self(effectOpacity: 0, animates: false)
        case .spectrum:
            Self.resolve(style: .aurora)
        }
    }
}

enum LyrisLinkedEffectMotionPolicy {
    static let framesPerSecond = LyrisAmbientParticleRenderPolicy.framesPerSecond

    static func timelineIsPaused(style: LinkedEffectStyle) -> Bool {
        !style.normalized.profile.isEnabled
    }

    static func timelineIsPaused(
        style: LinkedEffectStyle,
        isActive: Bool
    ) -> Bool {
        !isActive || timelineIsPaused(style: style)
    }

    static func phaseScale(isPlaying: Bool) -> Double {
        isPlaying ? 1 : 0.28
    }
}

struct LyrisLinkedEffectOverlay: View {
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin
    let isPlaying: Bool
    var isActive = true
    var framesPerSecond = Double(LyrisLinkedEffectMotionPolicy.framesPerSecond)
    var seed: String = "lyris-global-ambient"
    var progress: Double = 0.5

    var body: some View {
        let resolvedStyle = style.normalized
        TimelineView(
            .animation(
                minimumInterval: 1 / Double(
                    max(framesPerSecond, 1)
                ),
                paused: LyrisLinkedEffectMotionPolicy.timelineIsPaused(
                    style: resolvedStyle,
                    isActive: isActive
                )
            )
        ) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                * LyrisLinkedEffectMotionPolicy.phaseScale(
                    isPlaying: isPlaying
                )
            GeometryReader { proxy in
                effect(
                    style: resolvedStyle,
                    in: proxy.size,
                    phase: phase
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func effect(
        style: LinkedEffectStyle,
        in size: CGSize,
        phase: TimeInterval
    ) -> some View {
        if style.profile.isEnabled {
            let profile = style.profile
            let pulse = style == .pulse
                ? 0.78 + 0.22 * sin(phase * profile.animationRate * 2.1)
                : 1.0
            let travel = CGFloat(sin(phase * profile.animationRate))
            let counterTravel = CGFloat(cos(phase * profile.animationRate * 0.82))

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                skin.accentColor.opacity(0.30 * pulse),
                                skin.accentColor.opacity(0.08 * pulse),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(size.width * 0.34, 1)
                        )
                    )
                    .frame(width: size.width * 0.74, height: size.height * 2.8)
                    .offset(
                        x: -size.width * 0.25 + travel * size.width * 0.13,
                        y: size.height * 0.30
                    )
                    .blur(radius: profile.glowRadius * 0.62)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                skin.secondaryAccentColor.opacity(0.20 * pulse),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(size.width * 0.25, 1)
                        )
                    )
                    .frame(width: size.width * 0.58, height: size.height * 2.4)
                    .offset(
                        x: size.width * 0.30 + counterTravel * size.width * 0.11,
                        y: -size.height * 0.32
                    )
                    .blur(radius: profile.glowRadius * 0.72)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.045 * pulse),
                        .clear,
                        Color.black.opacity(0.18),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas(
                    opaque: false,
                    colorMode: .linear,
                    rendersAsynchronously: true
                ) { context, canvasSize in
                    let count = LyrisAmbientParticleRenderPolicy.count(
                        for: canvasSize.width
                    )
                    let particles = LyrisAmbientParticleModel.particles(
                        count: count,
                        seed: seed
                    )
                    for particle in particles {
                        let normalized = LyrisAmbientParticleModel.normalizedPosition(
                            for: particle,
                            phase: phase * profile.animationRate
                        )
                        let centerWeight = 0.50
                            + 0.50 * max(0, 1 - abs(normalized.x - 0.5) * 2)
                        let pulseBoost = style == .pulse ? pulse : 1
                        let color: Color
                        if particle.colorMix < 0.12 {
                            color = Color.white
                        } else if particle.colorMix < 0.56 {
                            color = skin.accentColor
                        } else {
                            color = skin.secondaryAccentColor
                        }
                        let radius = particle.radius * (style == .pulse ? 1.12 : 1)
                        let rect = CGRect(
                            x: normalized.x * canvasSize.width - radius,
                            y: normalized.y * canvasSize.height - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(
                                color.opacity(
                                    particle.opacity * centerWeight * pulseBoost
                                )
                            )
                        )
                    }

                    // A restrained cluster around the playhead ties particles,
                    // lyric timing, and transport progress into one system.
                    let playhead = min(max(progress, 0), 1)
                    for index in 0..<9 {
                        let angle = phase * 0.24 + Double(index) * 0.92
                        let orbit = CGFloat(4 + (index % 3) * 3)
                        let radius = CGFloat(index.isMultiple(of: 3) ? 1.35 : 0.82)
                        let center = CGPoint(
                            x: playhead * canvasSize.width + cos(angle) * orbit,
                            y: canvasSize.height * 0.58 + sin(angle * 1.17) * orbit
                        )
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: center.x - radius,
                                    y: center.y - radius,
                                    width: radius * 2,
                                    height: radius * 2
                                )
                            ),
                            with: .color(
                                skin.accentColor.opacity(0.09 + Double(index % 4) * 0.025)
                            )
                        )
                    }
                }
                .blur(radius: 0.14)
            }
            .blendMode(.screen)
        } else {
            Color.clear
        }
    }
}

struct LyrisLinkedEffectPreview: View {
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
            LyrisLinkedEffectOverlay(style: style, skin: skin, isPlaying: true)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            LyrisGlobalFlowThreadOverlay(
                style: style,
                skin: skin,
                isPlaying: true,
                seed: "linked-effect-preview-\(style.rawValue)"
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 12) {
                LyrisWaveformView(
                    trackID: "linked-effect-preview-\(style.rawValue)",
                    progress: 0.64,
                    isPlaying: true,
                    accentColor: skin.accentColor
                )
                .frame(width: 132, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.displayName(in: .simplifiedChinese))
                        .font(.headline)
                    Text(previewDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
        }
    }

    private var previewDescription: String {
        switch style.normalized {
        case .aurora: "粒子沿交织流光缓慢漂移"
        case .pulse: "粒子与流光随节奏呼吸"
        case .off: "关闭全局粒子与流光联动"
        case .spectrum: "粒子沿交织流光缓慢漂移"
        }
    }
}

struct LyrisArtworkView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.11, blue: 0.075),
                    Color(red: 0.01, green: 0.025, blue: 0.018),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(LyrisTheme.accent.opacity(0.82))
        }
    }
}

struct LyrisPlayerArtworkVisual: View {
    @ObservedObject var store: LyrisStore
    let mode: LyrisArtworkPresentationMode

    var body: some View {
        Group {
            if mode == .ambientMotion {
                TimelineView(
                    .animation(
                        minimumInterval: 1 / 24,
                        paused: !store.playback.isPlaying
                    )
                ) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        LyrisArtworkView(url: store.playback.track.artworkURL)
                            .scaleEffect(1.035 + 0.012 * sin(phase * 0.42))
                            .offset(
                                x: 1.8 * cos(phase * 0.31),
                                y: 1.5 * sin(phase * 0.27)
                            )
                        LinearGradient(
                            colors: [
                                store.interfaceSkin.accentColor.opacity(0.16),
                                .clear,
                                store.interfaceSkin.secondaryAccentColor.opacity(0.12),
                            ],
                            startPoint: UnitPoint(
                                x: 0.12 + 0.08 * cos(phase * 0.19),
                                y: 0.08
                            ),
                            endPoint: UnitPoint(
                                x: 0.86,
                                y: 0.90 + 0.06 * sin(phase * 0.23)
                            )
                        )
                        .blendMode(.screen)
                    }
                }
            } else {
                LyrisArtworkView(url: store.playback.track.artworkURL)
            }
        }
        .accessibilityLabel(
            mode == .staticArtwork ? "静态封面" : "氛围动效封面"
        )
    }
}

struct LyrisIconButton: View {
    let symbol: String
    var active = false
    var size: CGFloat = 34
    var foreground: Color? = nil
    var activeColor: Color = LyrisTheme.accent
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(
                    foreground ?? (active ? activeColor : LyrisTheme.primaryText)
                )
                .frame(width: size, height: size)
                .background(active ? activeColor.opacity(0.10) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

func lyrisTime(_ value: TimeInterval) -> String {
    guard value.isFinite else { return "0:00" }
    let seconds = max(0, Int(value.rounded()))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}
