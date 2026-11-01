import SwiftUI
import AppKit
import CoreText

// Genera el icono (1024 px) y el fondo del DMG (1x y 2x) con el estilo de la app.
// Uso: Artwork <carpeta de fuentes> <carpeta de salida>

private let led = Color(red: 0.30, green: 0.70, blue: 1.0)
private let ledCore = Color(red: 0.78, green: 0.92, blue: 1.0)
private let ledOff = Color(red: 0.07, green: 0.12, blue: 0.21)
private let silk = Color(red: 0.82, green: 0.85, blue: 0.89)

private func wide(_ size: CGFloat) -> Font { .custom("Michroma-Regular", size: size) }

private struct Brushed: View {
    var body: some View {
        Canvas { ctx, size in
            var lines = Path()
            var y: CGFloat = 0, i = 0.0
            while y < size.height {
                if abs(sin(i * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1) > 0.5 {
                    lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                }
                y += 2.5; i += 1
            }
            ctx.fill(lines, with: .color(.white.opacity(0.03)))
        }
    }
}

/// Barras de LEDs con forma de curva de EQ; el LED superior de cada columna brilla en blanco.
private struct LEDBars: View {
    let levels: [Int]
    let segments: Int
    let glow: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let cols = levels.count
            let gapX = size.width * 0.034
            let w = (size.width - gapX * CGFloat(cols - 1)) / CGFloat(cols)
            let step = size.height / CGFloat(segments)
            let h = step * 0.68
            var on = Path(), hot = Path(), off = Path()
            for (c, lv) in levels.enumerated() {
                let x = CGFloat(c) * (w + gapX)
                for s in 0..<segments {
                    let y = size.height - CGFloat(s + 1) * step + (step - h) / 2
                    let p = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: h * 0.18)
                    if s < lv { s == lv - 1 ? hot.addPath(p) : on.addPath(p) } else { off.addPath(p) }
                }
            }
            ctx.fill(off, with: .color(ledOff))
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: led, radius: glow))
                l.fill(on, with: .color(led))
                l.fill(hot, with: .color(.white))
            }
        }
    }
}

struct IconView: View {
    var body: some View {
        ZStack {
            Color.clear
            ZStack {
                RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.21), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                Brushed().clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
                RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 5)
                VStack(spacing: 34) {
                    Text("MAD")
                        .font(wide(124)).tracking(4)
                        .foregroundStyle(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.6)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 3)
                    ZStack {
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.015, green: 0.03, blue: 0.06), Color(red: 0.03, green: 0.07, blue: 0.13)],
                                                 startPoint: .top, endPoint: .bottom))
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 5)
                        LEDBars(levels: [10, 8, 6, 4, 5, 6, 8, 10, 11], segments: 12, glow: 16)
                            .padding(.horizontal, 44).padding(.vertical, 40)
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
                    }
                    .frame(width: 636, height: 452)
                }
                .offset(y: 6)
            }
            .frame(width: 824, height: 824)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct DMGBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.135, blue: 0.15), Color(red: 0.06, green: 0.065, blue: 0.075)],
                           startPoint: .top, endPoint: .bottom)
            Brushed()
            // Placas metálicas bajo los nombres de los iconos: Finder los escribe en oscuro.
            ForEach([CGPoint(x: 160, y: 209), CGPoint(x: 480, y: 209), CGPoint(x: 240, y: 369), CGPoint(x: 400, y: 369)], id: \.x) { p in
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.9), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .frame(width: 140, height: 20)
                    .position(p)
            }
            VStack(spacing: 6) {
                Text("MAD EQUALIZER").font(wide(20)).tracking(3).foregroundStyle(silk)
                Text("16 BAND STEREO GRAPHIC EQ").font(wide(8)).tracking(2.5).foregroundStyle(led.opacity(0.85))
            }
            .position(x: 320, y: 46)
            // Flecha de la app a Aplicaciones
            Canvas { ctx, _ in
                var p = Path()
                p.move(to: CGPoint(x: 250, y: 140)); p.addLine(to: CGPoint(x: 384, y: 140))
                p.move(to: CGPoint(x: 370, y: 128)); p.addLine(to: CGPoint(x: 388, y: 140)); p.addLine(to: CGPoint(x: 370, y: 152))
                ctx.drawLayer { l in
                    l.addFilter(.shadow(color: led, radius: 6))
                    l.stroke(p, with: .color(ledCore), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
            }
            Text("DRAG TO APPLICATIONS").font(wide(8)).tracking(1.5).foregroundStyle(silk.opacity(0.8))
                .position(x: 320, y: 172)
            Text("ARRASTRA A APLICACIONES").font(wide(7)).tracking(1.2).foregroundStyle(silk.opacity(0.55))
                .position(x: 320, y: 187)
            Text("WON'T OPEN? READ ME  ·  ¿NO ABRE? LÉEME").font(wide(7)).tracking(1.5).foregroundStyle(led.opacity(0.85))
                .position(x: 320, y: 240)
        }
        .frame(width: 640, height: 400)
    }
}

@MainActor
func save<V: View>(_ view: V, scale: CGFloat, to path: String) {
    let r = ImageRenderer(content: view)
    r.scale = scale
    guard let cg = r.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        fatalError("No se pudo renderizar \(path)")
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("✓ \(path)")
}

@main
struct Artwork {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let fonts = args[1], out = args[2]
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: fonts + "/Michroma-Regular.ttf") as CFURL, .process, nil)
        save(IconView(), scale: 1, to: out + "/icon_1024.png")
        save(DMGBackground(), scale: 1, to: out + "/dmg_bg.png")
        save(DMGBackground(), scale: 2, to: out + "/dmg_bg@2x.png")
    }
}
