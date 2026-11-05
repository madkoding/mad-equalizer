import SwiftUI

// MARK: - Paleta y tipografía

enum Palette {
    static let led = Color(red: 0.30, green: 0.70, blue: 1.0)
    static let ledCore = Color(red: 0.78, green: 0.92, blue: 1.0)
    static let ledOff = Color(red: 0.06, green: 0.11, blue: 0.19)
    static let silk = Color(red: 0.82, green: 0.85, blue: 0.89)
    static let plateTop = Color(red: 0.125, green: 0.13, blue: 0.145)
    static let plateBottom = Color(red: 0.065, green: 0.07, blue: 0.08)
    static let well = Color(red: 0.03, green: 0.035, blue: 0.045)
    static let ink = Color(red: 0.04, green: 0.10, blue: 0.20)
    static let redZone = Color(red: 0.78, green: 0.12, blue: 0.10)
    static let redOff = Color(red: 0.20, green: 0.04, blue: 0.04)
}

extension Font {
    /// Michroma: extendida al estilo Eurostile Wide / Microgramma. Es mucho más ancha que una
    /// fuente normal, así que los tamaños se escalan para conservar la composición.
    static func wide(_ size: CGFloat) -> Font { .custom("Michroma-Regular", size: size * 0.64) }
    /// DSEG14 Classic Italic: display de 14 segmentos.
    static func seg(_ size: CGFloat) -> Font { .custom("DSEG14Classic-Italic", size: size) }
}

struct Silk: View {
    let text: String
    var size: CGFloat = 11
    var opacity: Double = 0.8
    init(_ text: String, _ size: CGFloat = 11, opacity: Double = 0.8) {
        self.text = text; self.size = size; self.opacity = opacity
    }
    var body: some View {
        Text(text).font(.wide(size)).tracking(size * 0.05).foregroundStyle(Palette.silk.opacity(opacity))
    }
}

/// Estado de arrastre que no necesita redibujar la vista.
final class DragStart: ObservableObject {
    var value: Float?
    var relative = false
}

/// Brillo de LED: núcleo claro con halo azul.
extension GraphicsContext {
    func glow(_ path: Path, _ color: Color = Palette.ledCore, halo: Color = Palette.led, radius: CGFloat = 4) {
        drawLayer { l in
            l.addFilter(.shadow(color: halo, radius: radius))
            l.fill(path, with: .color(color))
        }
    }
}

// MARK: - Display de 14 segmentos

/// Caracteres que DSEG14 dibuja bien; el resto se convierte en celda vacía ("!").
func segSafe(_ s: String) -> String {
    let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-+")
    return String(s.folding(options: .diacriticInsensitive, locale: nil).uppercased().map { allowed.contains($0) ? $0 : "!" })
}

func segDB(_ v: Double, min lo: Double = -99) -> String {
    v.isFinite && v > lo ? String(format: "%.1f", v) : "----"
}

struct SegText: View {
    let text: String
    let cells: Int
    var size: CGFloat = 22
    var leading = false
    init(_ text: String, cells: Int, size: CGFloat = 22, leading: Bool = false) {
        self.text = text; self.cells = cells; self.size = size; self.leading = leading
    }
    var body: some View {
        let visible = text.filter { $0 != "." }.count
        let pad = String(repeating: "!", count: max(0, cells - visible))
        ZStack(alignment: leading ? .leading : .trailing) {
            Text(String(repeating: "~", count: cells)).foregroundStyle(Palette.led.opacity(0.07))
            Text(leading ? text + pad : pad + text)
                .foregroundStyle(Palette.ledCore)
                .shadow(color: Palette.led, radius: size * 0.12)
                .shadow(color: Palette.led.opacity(0.55), radius: size * 0.4)
        }
        .font(.seg(size))
        .fixedSize()
    }
}

struct Marquee: View {
    let text: String
    let cells: Int
    var size: CGFloat = 20
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { ctx in
            SegText(window(ctx.date), cells: cells, size: size, leading: true)
        }
    }
    private func window(_ d: Date) -> String {
        let chars = Array(text)
        guard chars.count > cells else { return text }
        let loop = chars + Array("!!!!")
        let off = Int(d.timeIntervalSinceReferenceDate / 0.35) % loop.count
        return String((0..<cells).map { loop[(off + $0) % loop.count] })
    }
}

/// Indicador tipo LCARS.
struct Lamp: View {
    let text: String
    let on: Bool
    init(_ text: String, _ on: Bool) { self.text = text; self.on = on }
    var body: some View {
        Text(text).font(.wide(10)).tracking(0.6)
            .foregroundStyle(on ? Color.black.opacity(0.85) : Palette.led.opacity(0.35))
            .padding(.horizontal, 8).frame(height: 16)
            .background(Capsule().fill(on ? Palette.led : Palette.ledOff))
            .shadow(color: on ? Palette.led.opacity(0.8) : .clear, radius: 5)
            .fixedSize()
    }
}

/// Barra horizontal de LEDs: bipolar desde el centro (correlación) o desde la derecha (reducción de ganancia).
struct BarMeter: View {
    let label: String
    let value: Double
    var bipolar = false
    var fromRight = false
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.wide(9)).foregroundStyle(Palette.led.opacity(0.6)).frame(width: 34, alignment: .leading)
            Canvas { ctx, size in
                let n = 21, c = n / 2
                let w = size.width / CGFloat(n)
                var on = Path(), warn = Path(), off = Path(), mid = Path()
                let t = Int((value * Double(bipolar ? c : n)).rounded())
                for i in 0..<n {
                    let p = Path(roundedRect: CGRect(x: CGFloat(i) * w + 1, y: 0, width: w - 2, height: size.height), cornerRadius: 1)
                    let lit: Bool
                    if bipolar { lit = i >= min(c, c + t) && i <= max(c, c + t) && t != 0 }
                    else if fromRight { lit = i >= n - t }
                    else { lit = i < t }
                    if lit { (bipolar && i < c) || (fromRight && i < n - 14) ? warn.addPath(p) : on.addPath(p) }
                    else if bipolar && i == c { mid.addPath(p) }
                    else { off.addPath(p) }
                }
                ctx.fill(off, with: .color(Palette.ledOff))
                ctx.fill(mid, with: .color(Palette.led.opacity(0.4)))
                ctx.glow(on)
                ctx.glow(warn, Palette.redZone, halo: Palette.redZone, radius: 3)
            }
            .frame(width: 118, height: 7)
        }
    }
}

struct Glass: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [Color(red: 0.015, green: 0.03, blue: 0.055), Color(red: 0.03, green: 0.065, blue: 0.11)],
                                 startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: .black, radius: 6, y: 2)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.14)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center))
                .allowsHitTesting(false))
    }
}

struct DisplayPanel: View {
    @ObservedObject var eq: EQModel
    @ObservedObject var meters: MeterModel

    private func field<V: View>(_ label: String, _ content: V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.wide(9)).tracking(0.8).foregroundStyle(Palette.led.opacity(0.6))
            content
        }
    }

    var body: some View {
        let b = eq.selectedBand
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 14) {
                Button { eq.showOutputs.toggle() } label: {
                    field("OUTPUT ▾", Marquee(text: segSafe(eq.outputName), cells: 10, size: 20))
                }
                .buttonStyle(.plain)
                .help("Elegir salida de audio")
                .popover(isPresented: $eq.showOutputs, arrowEdge: .bottom) { OutputList(eq: eq) }
                Spacer(minLength: 0)
                field("BAND", SegText(String(format: "%02d", b + 1), cells: 2, size: 20))
                field("FREQ HZ", SegText(bandSeg[b], cells: 5, size: 20))
                field("GAIN DB", SegText(String(format: "%+.1f", eq.gain(b)), cells: 4, size: 20))
            }
            HStack(alignment: .top, spacing: 12) {
                field("LUFS M", SegText(segDB(meters.lufsM), cells: 4, size: 15))
                field("LUFS S", SegText(segDB(meters.lufsS), cells: 4, size: 15))
                Button { meters.resetIntegrated() } label: {
                    field("LUFS I", SegText(segDB(meters.lufsI), cells: 4, size: 15))
                }
                .buttonStyle(.plain)
                .help("Clic para reiniciar el loudness integrado")
                field("PEAK", SegText(segDB(meters.peakHoldDB), cells: 4, size: 15))
                field("CREST", SegText(meters.crestDB > 0 ? String(format: "%.1f", meters.crestDB) : "---", cells: 3, size: 15))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 8) {
                    BarMeter(label: "CORR", value: meters.corr, bipolar: true)
                    BarMeter(label: "GR", value: min(-meters.grDB / 12, 1), fromRight: true)
                }
                .padding(.top, 3)
            }
            HStack(spacing: 5) {
                Lamp("TAP", eq.running)
                Lamp("SIGNAL", meters.signal)
                Lamp("EQ", eq.running && !eq.bypass)
                Lamp("BYPASS", eq.bypass)
                Lamp(eq.autoGain ? String(format: "AUTO %+.1f", eq.autoGainDB) : "AUTO", eq.autoGain)
                Lamp(eq.channelMode.label, eq.channelMode != .link || eq.isSplit)
                Spacer(minLength: 6)
                Text(eq.status).font(.wide(10)).tracking(0.5)
                    .foregroundStyle(Palette.led.opacity(0.75)).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Glass())
    }
}

struct OutputList: View {
    @ObservedObject var eq: EQModel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SALIDA DE AUDIO").font(.wide(11)).tracking(1).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(eq.realOutputs) { d in
                Button { eq.selectOutput(d) } label: {
                    HStack {
                        Image(systemName: d.id == eq.currentOutput ? "checkmark" : "").frame(width: 14)
                        Text(d.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(minWidth: 240)
    }
}

struct AppsList: View {
    @ObservedObject var eq: EQModel
    var body: some View {
        let apps = eq.runningApps()
        VStack(alignment: .leading, spacing: 6) {
            Text("EXCLUIR DEL ECUALIZADOR").font(.wide(11)).tracking(1).foregroundStyle(.secondary)
            Text("Las apps marcadas suenan directo, sin procesar.").font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(apps) { a in
                        Toggle(isOn: Binding(get: { eq.excludedApps.contains(a.id) }, set: { eq.setExcluded(a.id, $0) })) {
                            HStack(spacing: 6) {
                                if let icon = a.icon {
                                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "app.dashed").frame(width: 16, height: 16)
                                }
                                Text(a.name).lineLimit(1)
                                if a.playing {
                                    Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(12)
        .frame(width: 300)
    }
}

// MARK: - Medidor VU con peak meter

struct Bezel {
    static func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10),
                 with: .linearGradient(Gradient(colors: [Color(white: 0.24), Color(white: 0.07)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }
}

struct VUMeter: View {
    let position: Double
    let channel: String
    let peak: Double
    let over: Bool

    private func pos(_ db: Double) -> Double { (pow(10, db / 20) - 0.1) / (pow(10, 0.15) - 0.1) }

    var body: some View {
        Canvas { ctx, size in
            Bezel.draw(ctx, size)
            let face = CGRect(x: 9, y: 9, width: size.width - 18, height: size.height - 18 - 20)
            let facePath = Path(roundedRect: face, cornerRadius: 5)
            ctx.fill(facePath, with: .radialGradient(
                Gradient(colors: [Color(red: 0.90, green: 0.96, blue: 1.0), Color(red: 0.64, green: 0.82, blue: 0.97),
                                  Color(red: 0.28, green: 0.48, blue: 0.72)]),
                center: CGPoint(x: face.midX, y: face.maxY), startRadius: 0, endRadius: face.width * 0.85))

            ctx.drawLayer { l in
                l.clip(to: facePath)
                // El arco (con sus números) debe caber a lo ancho; el pivote queda bajo la tapa inferior.
                let R = min(face.height * 0.8, (face.width / 2 - 20) / sin(40 * .pi / 180) - 16)
                let pivot = CGPoint(x: face.midX, y: face.minY + 34 + R)
                func pt(_ p: Double, _ r: CGFloat) -> CGPoint {
                    let a = (-40 + 80 * p) * .pi / 180
                    return CGPoint(x: pivot.x + r * CGFloat(sin(a)), y: pivot.y - r * CGFloat(cos(a)))
                }
                let p0 = pos(0)
                var arc = Path()
                for k in 0...40 { let p = p0 * Double(k) / 40; k == 0 ? arc.move(to: pt(p, R)) : arc.addLine(to: pt(p, R)) }
                l.stroke(arc, with: .color(Palette.ink), lineWidth: 1.2)
                var red = Path()
                for k in 0...20 { let p = p0 + (1 - p0) * Double(k) / 20; k == 0 ? red.move(to: pt(p, R + 2)) : red.addLine(to: pt(p, R + 2)) }
                l.stroke(red, with: .color(Palette.redZone), lineWidth: 5)

                let marks: [(Double, String)] = [(-20, "20"), (-10, "10"), (-7, "7"), (-5, "5"), (-3, "3"), (-2, "2"),
                                                 (-1, "1"), (0, "0"), (1, "1"), (2, "2"), (3, "3")]
                for (db, lab) in marks {
                    let p = pos(db), c = db > 0 ? Palette.redZone : Palette.ink
                    var t = Path(); t.move(to: pt(p, R - 3)); t.addLine(to: pt(p, R + 7))
                    l.stroke(t, with: .color(c), lineWidth: db == 0 ? 1.8 : 1.1)
                    l.draw(Text(lab).font(.wide(10)).foregroundColor(c), at: pt(p, R + 16))
                }
                for db in [-15.0, -8.5, -6, -4, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5] {
                    var t = Path(); t.move(to: pt(pos(db), R)); t.addLine(to: pt(pos(db), R + 4))
                    l.stroke(t, with: .color(db > 0 ? Palette.redZone : Palette.ink), lineWidth: 0.8)
                }
                l.draw(Text("VU").font(.wide(22)).foregroundColor(Palette.ink),
                       at: CGPoint(x: face.midX, y: face.maxY - face.height * 0.36))
                l.draw(Text(channel).font(.wide(9)).tracking(1).foregroundColor(Palette.ink.opacity(0.75)),
                       at: CGPoint(x: face.minX + 24, y: face.maxY - 11))
                l.draw(Text("MAD").font(.wide(9)).tracking(1).foregroundColor(Palette.ink.opacity(0.75)),
                       at: CGPoint(x: face.maxX - 22, y: face.maxY - 11))

                var needle = Path()
                needle.move(to: pt(position, 0))
                needle.addLine(to: pt(position, R + 12))
                l.drawLayer { s in
                    s.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 2, y: 2))
                    s.stroke(needle, with: .color(Color(red: 0.07, green: 0.07, blue: 0.09)),
                             style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
                let cover = Path(ellipseIn: CGRect(x: face.midX - face.width * 0.3, y: face.maxY - 14,
                                                   width: face.width * 0.6, height: 40))
                l.fill(cover, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.05)]),
                                                    startPoint: CGPoint(x: 0, y: face.maxY - 14),
                                                    endPoint: CGPoint(x: 0, y: face.maxY + 8)))
                l.fill(Path(face), with: .linearGradient(Gradient(colors: [.white.opacity(0.24), .white.opacity(0)]),
                                                         startPoint: CGPoint(x: face.minX, y: face.minY),
                                                         endPoint: CGPoint(x: face.minX + face.width * 0.35, y: face.midY)))
            }
            ctx.stroke(facePath, with: .color(.black), lineWidth: 1.5)

            // Peak meter: -40 a 0 dBFS, los últimos 4 segmentos (> -6 dB) en blanco, y OVER
            let y = face.maxY + 7
            ctx.draw(Text("PK").font(.wide(9)).foregroundColor(Palette.silk.opacity(0.6)), at: CGPoint(x: face.minX + 8, y: y + 4))
            let overW: CGFloat = 36
            let x0 = face.minX + 20, segW = face.width - 20 - overW - 6
            let n = 24, sw = segW / CGFloat(n)
            let lit = Int((peak * Double(n)).rounded())
            var on = Path(), hot = Path(), off = Path()
            for i in 0..<n {
                let p = Path(roundedRect: CGRect(x: x0 + CGFloat(i) * sw + 0.75, y: y, width: sw - 1.5, height: 8), cornerRadius: 1)
                if i < lit { i >= n - 4 ? hot.addPath(p) : on.addPath(p) } else { off.addPath(p) }
            }
            ctx.fill(off, with: .color(Palette.ledOff))
            ctx.glow(on, Palette.led, radius: 3)
            ctx.glow(hot, .white, radius: 3)
            let overRect = CGRect(x: face.maxX - overW, y: y - 1, width: overW, height: 10)
            let overPath = Path(roundedRect: overRect, cornerRadius: 2)
            if over { ctx.glow(overPath, Palette.redZone, halo: Palette.redZone, radius: 5) }
            else { ctx.fill(overPath, with: .color(Palette.redOff)) }
            ctx.draw(Text("OVER").font(.wide(8)).foregroundColor(over ? .white : Color(red: 0.5, green: 0.22, blue: 0.22)),
                     at: CGPoint(x: overRect.midX, y: overRect.midY))
        }
        .shadow(color: Palette.led.opacity(0.3), radius: 14)
    }
}

struct VUMeterView: View {
    @ObservedObject var meters: MeterModel
    let left: Bool
    var body: some View {
        VUMeter(position: left ? meters.left : meters.right, channel: left ? "LEFT" : "RIGHT",
                peak: left ? meters.peakL : meters.peakR, over: left ? meters.overL : meters.overR)
    }
}

// MARK: - Faders

struct LEDLadder: View {
    let value: Float
    let range: Float
    let margin: CGFloat
    static let count = 17

    var body: some View {
        Canvas { ctx, size in
            let n = Self.count, center = n / 2
            let span = size.height - 2 * margin
            let ledH = max(3, span / CGFloat(n - 1) * 0.55)
            let litTo = center - Int((value / (range / 8)).rounded())
            let lo = min(center, litTo), hi = max(center, litTo)
            var lit = Path(), off = Path(), mid = Path()
            for i in 0..<n {
                let cy = margin + span * CGFloat(i) / CGFloat(n - 1)
                let p = Path(roundedRect: CGRect(x: 0, y: cy - ledH / 2, width: size.width, height: ledH), cornerRadius: 1.2)
                if litTo != center && i >= lo && i <= hi { lit.addPath(p) }
                else if i == center { mid.addPath(p) }
                else { off.addPath(p) }
            }
            ctx.fill(off, with: .color(Palette.ledOff))
            ctx.fill(mid, with: .color(Palette.led.opacity(0.4)))
            ctx.glow(lit)
        }
    }
}

/// Analizador: barra desde abajo, los tres LEDs superiores más calientes y un punto de pico retenido.
struct SpectrumLadder: View {
    let level: Double
    let peak: Double
    let margin: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let n = LEDLadder.count
            let span = size.height - 2 * margin
            let ledH = max(3, span / CGFloat(n - 1) * 0.55)
            let lit = Int(level.rounded())
            let peakLED = Int(peak.rounded()) - 1
            var on = Path(), hot = Path(), off = Path(), pk = Path()
            for k in 0..<n {   // k = 0 es el LED de abajo
                let cy = margin + span * CGFloat(n - 1 - k) / CGFloat(n - 1)
                let p = Path(roundedRect: CGRect(x: 0, y: cy - ledH / 2, width: size.width, height: ledH), cornerRadius: 1.2)
                if k < lit { k >= n - 3 ? hot.addPath(p) : on.addPath(p) }
                else if k == peakLED && peakLED >= 0 { pk.addPath(p) }
                else { off.addPath(p) }
            }
            ctx.fill(off, with: .color(Palette.ledOff))
            ctx.glow(on, Palette.led)
            ctx.glow(pk)
            ctx.glow(hot, .white)
        }
    }
}

struct BandLEDs: View {
    @ObservedObject var meters: MeterModel
    let band: Int
    let gain: Float
    let range: Float
    let spectrum: Bool
    let margin: CGFloat
    var body: some View {
        if spectrum {
            SpectrumLadder(level: meters.levels[band], peak: meters.peaks[band], margin: margin)
        } else {
            LEDLadder(value: gain, range: range, margin: margin)
        }
    }
}

struct FaderCap: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(stops: [.init(color: Color(white: 0.93), location: 0),
                                             .init(color: Color(white: 0.62), location: 0.46),
                                             .init(color: Color(white: 0.82), location: 0.54),
                                             .init(color: Color(white: 0.42), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.75), lineWidth: 0.6)
            VStack(spacing: 9) {
                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.7)
                Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.7)
            }.padding(.horizontal, 5)
            Rectangle().fill(Palette.ledCore).frame(height: 2).padding(.horizontal, 3)
                .shadow(color: Palette.led, radius: 3)
        }
        .shadow(color: .black.opacity(0.75), radius: 2.5, y: 2.5)
    }
}

struct Fader: View {
    @Binding var value: Float
    var range: Float = 12
    var onTouch: () -> Void = {}
    @StateObject private var drag = DragStart()
    static let cap = CGSize(width: 30, height: 18)

    var body: some View {
        GeometryReader { g in
            let cap = Self.cap
            let usable = g.size.height - cap.height
            let y = CGFloat((range - value) / (2 * range)) * usable + cap.height / 2
            ZStack {
                Canvas { ctx, size in
                    for k in 0...8 {
                        let ty = cap.height / 2 + usable * CGFloat(k) / 8
                        let long = k % 4 == 0
                        let w: CGFloat = long ? 7 : 4
                        let c = GraphicsContext.Shading.color(Palette.silk.opacity(long ? 0.5 : 0.22))
                        ctx.fill(Path(CGRect(x: 0, y: ty - 0.5, width: w, height: 1)), with: c)
                        ctx.fill(Path(CGRect(x: size.width - w, y: ty - 0.5, width: w, height: 1)), with: c)
                    }
                }
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.black.shadow(.inner(color: .black, radius: 2)))
                    .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                    .frame(width: 5, height: usable + 6)
                FaderCap()
                    .frame(width: cap.width, height: cap.height)
                    .position(x: g.size.width / 2, y: y)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    onTouch()
                    if drag.value == nil {
                        // Agarrar la perilla la mueve en relativo; tocar el riel salta a ese punto.
                        drag.relative = abs(e.startLocation.y - y) <= cap.height
                        drag.value = value
                    }
                    let v: Float
                    if drag.relative {
                        v = drag.value! - Float(e.translation.height / usable) * 2 * range
                    } else {
                        let t = min(max((e.location.y - cap.height / 2) / usable, 0), 1)
                        v = range - Float(t) * 2 * range
                    }
                    let step: Float = range > 6 ? 0.5 : 0.25
                    value = (min(max(v, -range), range) / step).rounded() * step
                }
                .onEnded { _ in drag.value = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = 0 })
        }
    }
}

struct BandColumn: View {
    @Binding var gain: Float
    let band: Int
    let meters: MeterModel
    let spectrum: Bool
    let range: Float
    let label: String
    let selected: Bool
    let onTouch: () -> Void
    static let height: CGFloat = 295
    static let width: CGFloat = 46
    static let spacing: CGFloat = 8
    /// Centro de la perilla dentro de la columna (LEDs 7 + 4 de separación + medio fader).
    static let faderCenter: CGFloat = (width - 41) / 2 + 7 + 4 + 15

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 4) {
                BandLEDs(meters: meters, band: band, gain: gain, range: range, spectrum: spectrum, margin: Fader.cap.height / 2)
                    .frame(width: 7)
                Fader(value: $gain, range: range, onTouch: onTouch).frame(width: 30)
            }
            .frame(height: Self.height)
            Text(label).font(.wide(11))
                .foregroundStyle(selected ? Palette.ledCore : Palette.silk.opacity(0.7))
                .shadow(color: selected ? Palette.led : .clear, radius: 4)
        }
        .frame(width: Self.width)
    }
}

struct DBScale: View {
    let range: Float
    static let width: CGFloat = 32
    var body: some View {
        let usable = BandColumn.height - Fader.cap.height
        let r = Int(range)
        ZStack {
            ForEach([r, r / 2, 0, -r / 2, -r], id: \.self) { v in
                Text(v > 0 ? "+\(v)" : "\(v)").font(.wide(10))
                    .foregroundStyle(Palette.silk.opacity(0.5))
                    .position(x: 16, y: Fader.cap.height / 2 + usable * CGFloat(r - v) / CGFloat(2 * r))
            }
        }
        .frame(width: Self.width, height: BandColumn.height)
    }
}

/// Respuesta real (suma de todas las bandas y filtros), alineada con los faders.
struct ResponseCurve: View {
    let left: [Double]
    let right: [Double]
    let split: Bool
    let range: Float

    var body: some View {
        Canvas { ctx, _ in
            guard left.count == curvePoints, right.count == curvePoints else { return }
            let x0 = DBScale.width + BandColumn.spacing + BandColumn.faderCenter
            let x1 = x0 + 15 * (BandColumn.width + BandColumn.spacing)
            let usable = BandColumn.height - Fader.cap.height
            let r = Double(range)
            func pt(_ k: Int, _ db: Double) -> CGPoint {
                let t = CGFloat(log(curveFreqs[k] / 20) / log(1000))
                let y = Fader.cap.height / 2 + usable * CGFloat((r - min(max(db, -r - 1.5), r + 1.5)) / (2 * r))
                return CGPoint(x: x0 + (x1 - x0) * t, y: y)
            }
            func path(_ c: [Double]) -> Path {
                var p = Path()
                for k in 0..<c.count { k == 0 ? p.move(to: pt(k, c[k])) : p.addLine(to: pt(k, c[k])) }
                return p
            }
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: Palette.led, radius: 4))
                l.stroke(path(left), with: .color(Palette.ledCore.opacity(0.8)), lineWidth: 1.6)
                if split {
                    l.stroke(path(right), with: .color(Palette.led.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Perillas y botones

struct Knob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let step: Float
    let label: String
    let readout: String
    var size: CGFloat = 54
    @StateObject private var drag = DragStart()

    var body: some View {
        VStack(spacing: 5) {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = min(size.width, size.height) / 2
                let t = Double((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                func at(_ a: Double, _ r: CGFloat) -> CGPoint {
                    CGPoint(x: c.x + r * CGFloat(sin(a)), y: c.y - r * CGFloat(cos(a)))
                }
                var on = Path(), off = Path()
                for i in 0..<21 {
                    let f = Double(i) / 20
                    let p = at((-135 + 270 * f) * .pi / 180, R - 3)
                    let dot = Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2))
                    if f <= t + 0.001 { on.addPath(dot) } else { off.addPath(dot) }
                }
                ctx.fill(off, with: .color(Palette.ledOff))
                ctx.glow(on, radius: 3)
                let bodyR = R - 9
                let body = Path(ellipseIn: CGRect(x: c.x - bodyR, y: c.y - bodyR, width: bodyR * 2, height: bodyR * 2))
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: .black.opacity(0.85), radius: 4, y: 3))
                    l.fill(body, with: .color(Color(white: 0.09)))
                }
                var knurl = Path()
                for i in 0..<48 {
                    let a = Double(i) / 48 * 2 * .pi
                    knurl.move(to: at(a, bodyR - 3)); knurl.addLine(to: at(a, bodyR))
                }
                ctx.stroke(knurl, with: .color(.white.opacity(0.2)), lineWidth: 1)
                let capR = bodyR * 0.74
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)),
                         with: .radialGradient(Gradient(colors: [Color(white: 0.86), Color(white: 0.55), Color(white: 0.28)]),
                                               center: CGPoint(x: c.x - capR * 0.35, y: c.y - capR * 0.45),
                                               startRadius: 0, endRadius: capR * 1.7))
                for k in stride(from: 0.3, to: 1.0, by: 0.15) {
                    let r = capR * k
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(0.06)), lineWidth: 0.6)
                }
                let a = (-135 + 270 * t) * .pi / 180
                var ptr = Path()
                ptr.move(to: at(a, capR * 0.3)); ptr.addLine(to: at(a, bodyR - 2))
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: Palette.led, radius: 3))
                    l.stroke(ptr, with: .color(Palette.ledCore), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { e in
                    if drag.value == nil { drag.value = value }
                    let span = range.upperBound - range.lowerBound
                    let v = drag.value! - Float(e.translation.height) / 160 * span
                    value = (min(max(v, range.lowerBound), range.upperBound) / step).rounded() * step
                }
                .onEnded { _ in drag.value = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
            SegText(readout, cells: 4, size: 10)
            Silk(label, 10)
        }
        .frame(width: 74)
    }
}

struct KeyStyle: ButtonStyle {
    var width: CGFloat = 66
    /// LED del botón: barra en su borde superior; encendida = ese botón está activo.
    var on = false
    var dim = false
    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        return configuration.label
            .font(.wide(10)).tracking(0.4)
            .foregroundStyle(Palette.silk.opacity(0.9))
            .lineLimit(1)
            .padding(.top, 2)
            .frame(width: width, height: 24)
            .background(RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: p ? [Color(white: 0.09), Color(white: 0.15)] : [Color(white: 0.25), Color(white: 0.11)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.9), lineWidth: 1))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(on ? Palette.ledCore : dim ? Palette.led.opacity(0.35) : Palette.ledOff)
                    .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color.black.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: on ? Palette.led : .clear, radius: 4)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
            }
            .shadow(color: .black.opacity(0.65), radius: p ? 0.5 : 2, y: p ? 0 : 2)
            .offset(y: p ? 1 : 0)
    }
}

struct LEDKey: View {
    let title: String
    let on: Bool
    var dim = false
    let action: () -> Void
    init(_ title: String, on: Bool, dim: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.on = on; self.dim = dim; self.action = action
    }
    var body: some View {
        Button(title, action: action).buttonStyle(KeyStyle(on: on, dim: dim))
    }
}

/// STORE parpadea mientras espera que elijas la memoria donde guardar.
struct StoreKey: View {
    @ObservedObject var eq: EQModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { ctx in
            let blink = Int(ctx.date.timeIntervalSinceReferenceDate / 0.3) % 2 == 0
            LEDKey("STORE", on: eq.storeArmed && blink) { eq.storeArmed.toggle() }
                .help("Pulsa STORE y luego M1–M4 para guardar")
        }
    }
}

struct RowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.wide(10)).tracking(0.8)
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: 64, height: 18, alignment: .trailing)
            .padding(.trailing, 8)
            .background(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9)
                .fill(Palette.led.opacity(0.85)))
            .padding(.top, 3)
    }
}

struct PowerButton: View {
    let on: Bool
    let action: () -> Void
    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                ZStack {
                    Circle().fill(Color.black).frame(width: 52, height: 52)
                    Circle().stroke(on ? Palette.ledCore : Palette.ledOff, lineWidth: 2.5)
                        .frame(width: 47, height: 47)
                        .shadow(color: on ? Palette.led : .clear, radius: 6)
                    Circle().fill(RadialGradient(colors: [Color(white: 0.82), Color(white: 0.45), Color(white: 0.22)],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 30))
                        .frame(width: 38, height: 38)
                    Image(systemName: "power").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(on ? Palette.led : Color.black.opacity(0.55))
                        .shadow(color: on ? Palette.led : .clear, radius: 4)
                }
            }
            .buttonStyle(.plain)
            .help(on ? "Apagar ecualizador" : "Encender ecualizador")
            Silk("POWER", 11)
        }
    }
}

// MARK: - Chasis

struct Faceplate: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Palette.plateTop, Palette.plateBottom]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            var lines = Path()
            var y: CGFloat = 0, i = 0.0
            while y < size.height {
                if abs(sin(i * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1) > 0.5 {
                    lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.6))
                }
                y += 1.5; i += 1
            }
            ctx.fill(lines, with: .color(.white.opacity(0.025)))
        }
    }
}

struct WoodCheek: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.19, green: 0.10, blue: 0.05),
                                                             Color(red: 0.36, green: 0.20, blue: 0.11),
                                                             Color(red: 0.23, green: 0.12, blue: 0.06)]),
                                           startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            for k in 0..<10 {
                var p = Path()
                let x0 = size.width * (CGFloat(k) + 0.5) / 10
                p.move(to: CGPoint(x: x0, y: 0))
                for yy in stride(from: CGFloat(0), through: size.height, by: 6) {
                    p.addLine(to: CGPoint(x: x0 + 1.6 * sin(yy / (37 + CGFloat(k) * 5) + CGFloat(k)), y: yy))
                }
                ctx.stroke(p, with: .color(Color.black.opacity(k % 2 == 0 ? 0.28 : 0.13)), lineWidth: k % 3 == 0 ? 1.2 : 0.6)
            }
            ctx.fill(Path(CGRect(x: size.width - 1, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.6)))
        }
    }
}

struct Screw: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.78), Color(white: 0.32)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: 7, height: 1.4).rotationEffect(.degrees(35))
        }
        .frame(width: 9, height: 9)
        .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
    }
}

// MARK: - Ventana principal

private struct CenterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct RootView: View {
    @StateObject private var eq = EQModel()
    @StateObject private var meters = MeterModel()
    @State private var vuHeight: CGFloat = 159
    static let size = CGSize(width: 1120, height: 772)
    /// Franja superior de la ventana (zona de la barra de título oculta): lleva la serigrafía.
    static let strip: CGFloat = 28
    /// Lienzo completo de la ventana a escala 100 %.
    static let canvas = CGSize(width: size.width, height: size.height + strip)
    /// La ventana se puede redimensionar con la proporción fija; el mínimo es el 60 % del tamaño original.
    static let minScale: CGFloat = 0.6

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.strip)
                faceplate
            }
            .overlay(alignment: .top) {
                Silk("MAD EQUALIZER  ·  16 BAND STEREO GRAPHIC EQ  ·  SYSTEM AUDIO TAP", 10, opacity: 0.4).offset(y: 7)
            }
            .frame(width: Self.canvas.width, height: Self.canvas.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .frame(minWidth: Self.canvas.width * Self.minScale, minHeight: Self.canvas.height * Self.minScale)
        .background(WindowAspect(size: Self.canvas, minScale: Self.minScale))
        .titlebarColor(Color(red: 0.04, green: 0.045, blue: 0.05))
        .preferredColorScheme(.dark)
        .onAppear { meters.attach(eq) }
    }

    private var faceplate: some View {
        ZStack(alignment: .top) {
            Faceplate()
            HStack(spacing: 0) {
                WoodCheek().frame(width: 24)
                Spacer()
                WoodCheek().frame(width: 24).scaleEffect(x: -1)
            }
            VStack(spacing: 14) {
                header
                faderWell
                controls
            }
            .padding(.horizontal, 46)
            .padding(.top, 14)
            .padding(.bottom, 16)
            screws
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.5), Color(white: 0.25), Color(white: 0.5)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VUMeterView(meters: meters, left: true).frame(width: 230, height: vuHeight)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("MAD").font(.wide(36)).tracking(1).foregroundStyle(Palette.silk)
                    Text("EQUALIZER").font(.wide(12)).tracking(3).foregroundStyle(Palette.silk.opacity(0.55))
                    Spacer()
                    Text("16 BAND").font(.wide(12)).tracking(2).foregroundStyle(Palette.led.opacity(0.8))
                }
                DisplayPanel(eq: eq, meters: meters)
            }
            // Los VU miden lo mismo que este panel (marca + display) para quedar alineados.
            .background(GeometryReader { g in
                Color.clear.preference(key: CenterHeightKey.self, value: g.size.height)
            })
            VUMeterView(meters: meters, left: false).frame(width: 230, height: vuHeight)
        }
        .onPreferenceChange(CenterHeightKey.self) { if $0 > 100 { vuHeight = $0 } }
    }

    private var faderWell: some View {
        HStack(alignment: .top, spacing: BandColumn.spacing) {
            DBScale(range: eq.rangeDB)
            ForEach(0..<16, id: \.self) { i in
                BandColumn(gain: Binding(get: { eq.gain(i) }, set: { eq.setGain(i, $0) }),
                           band: i,
                           meters: meters,
                           spectrum: eq.spectrumMode && eq.running,
                           range: eq.rangeDB,
                           label: bandLabels[i],
                           selected: eq.selectedBand == i,
                           onTouch: { eq.selectedBand = i })
                    .onHover { if $0 { eq.selectedBand = i } }
            }
            DBScale(range: eq.rangeDB)
        }
        .background(alignment: .topLeading) {
            if eq.showCurve {
                ResponseCurve(left: eq.curveL, right: eq.curveR, split: eq.isSplit, range: eq.rangeDB)
            }
        }
        .padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Palette.well.shadow(.inner(color: .black, radius: 8, y: 3)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                              lineWidth: 1)))
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 6) {
            RowLabel(label)
            content()
        }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 16) {
            PowerButton(on: eq.running) { eq.togglePower() }
                .padding(.top, 6)
            VStack(spacing: 8) {
                LEDKey("BYPASS", on: eq.bypass) { eq.bypass.toggle() }
                LEDKey("SPECTRUM", on: eq.spectrumMode) { eq.spectrumMode.toggle() }
            }
            Rectangle().fill(Color.black.opacity(0.6)).frame(width: 1, height: 150)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1).offset(x: 1) }
            VStack(alignment: .leading, spacing: 8) {
                row("PRESET") {
                    ForEach(presets, id: \.name) { p in
                        LEDKey(p.name, on: eq.activePreset == p.name) { eq.applyPreset(p) }
                    }
                }
                row("FILTER") {
                    ForEach(filterDefs, id: \.id) { f in
                        LEDKey(f.name, on: eq.filters.contains(f.id)) { eq.toggleFilter(f.id) }
                    }
                }
                row("MEMORY") {
                    ForEach(0..<4, id: \.self) { i in
                        LEDKey("M\(i + 1)", on: eq.activeMemory == i, dim: eq.memories[i] != nil) { eq.pressMemory(i) }
                    }
                    StoreKey(eq: eq)
                    LEDKey("A", on: eq.abSlot == 0) { eq.selectAB(0) }
                    LEDKey("B", on: eq.abSlot == 1) { eq.selectAB(1) }
                }
                row("MODE") {
                    LEDKey("RANGE 6", on: eq.rangeDB == 6) { eq.toggleRange() }
                        .help("Faders de ±6 dB para ajuste fino")
                    LEDKey("PROP Q", on: eq.propQ) { eq.propQ.toggle() }
                        .help("Q proporcional: bandas más anchas con poca ganancia")
                    LEDKey(eq.channelMode.label, on: eq.channelMode != .link) { eq.cycleChannelMode() }
                        .help("Editar ambos canales, sólo el izquierdo o sólo el derecho")
                    LEDKey("AUTO GAIN", on: eq.autoGain) { eq.autoGain.toggle() }
                        .help("Compensa el volumen para comparar curvas a igual loudness")
                    LEDKey("CURVE", on: eq.showCurve) { eq.showCurve.toggle() }
                    LEDKey("APPS", on: !eq.excludedApps.isEmpty) { eq.showApps.toggle() }
                        .help("Excluir apps del ecualizador")
                        .popover(isPresented: $eq.showApps, arrowEdge: .top) { AppsList(eq: eq) }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Knob(value: $eq.preampDB, range: -12...12, defaultValue: 0, step: 0.5,
                         label: "PRE-AMP", readout: String(format: "%+.1f", eq.preampDB))
                    Knob(value: $eq.level, range: 0...1.5, defaultValue: 1, step: 0.01,
                         label: "LEVEL", readout: "\(Int((eq.level * 100).rounded()))")
                    Knob(value: Binding(get: { log10(eq.lowCutHz) }, set: { eq.lowCutHz = pow(10, $0) }),
                         range: log10(20)...log10(200), defaultValue: log10(80), step: 0.005,
                         label: "LOW CUT", readout: "\(Int(eq.lowCutHz.rounded()))")
                }
                HStack(spacing: 0) {
                    Knob(value: $eq.limitDB, range: -12...0, defaultValue: -0.5, step: 0.5,
                         label: "LIMIT", readout: String(format: "%.1f", eq.limitDB))
                    // Ancho estéreo (mid/side): 0 % = mono, 100 % = original, 200 % = lados al doble para separar instrumentos.
                    Knob(value: $eq.width, range: 0...2, defaultValue: 1, step: 0.01,
                         label: "WIDTH", readout: "\(Int((eq.width * 100).rounded()))")
                    Spacer().frame(width: 74)
                }
            }
        }
    }

    private var screws: some View {
        VStack {
            Spacer().frame(height: 10)
            HStack { Screw(); Spacer(); Screw() }
            Spacer()
            HStack { Screw(); Spacer(); Screw() }
            Spacer().frame(height: 10)
        }
        .padding(.horizontal, 32)
    }
}

extension View {
    /// Pinta la barra de título del color del chasis (macOS 15+); en macOS 14 queda la oscura del sistema.
    @ViewBuilder func titlebarColor(_ c: Color) -> some View {
        if #available(macOS 15.0, *) { containerBackground(c, for: .window) } else { self }
    }
}

/// Fija la proporción de la ventana y su tamaño mínimo; el contenido se escala con ella.
struct WindowAspect: NSViewRepresentable {
    let size: CGSize
    let minScale: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { configure(v.window) }
    }
    private func configure(_ w: NSWindow?) {
        guard let w else { return }
        w.contentAspectRatio = size
        w.contentMinSize = CGSize(width: size.width * minScale, height: size.height * minScale)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Cerrar la ventana cierra la app: el tap desaparece y el audio vuelve a la normalidad.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MADEqualizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("MAD Equalizer") { RootView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            .defaultSize(width: RootView.canvas.width, height: RootView.canvas.height)
    }
}
