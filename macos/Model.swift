import SwiftUI
import AppKit
import CoreAudio
import CoreGraphics
import ApplicationServices

// Bandas ISO de 2/3 de octava
let bandFreqs: [Double] = [20, 31.5, 50, 80, 125, 200, 315, 500, 800, 1250, 2000, 3150, 5000, 8000, 12500, 20000]
let bandLabels = ["20", "31", "50", "80", "125", "200", "315", "500", "800", "1.2K", "2K", "3.1K", "5K", "8K", "12K", "20K"]
let bandSeg = ["20", "31.5", "50", "80", "125", "200", "315", "500", "800", "1.25K", "2K", "3.15K", "5K", "8K", "12.5K", "20K"]

/// Puntos de la curva de respuesta: 20 Hz a 20 kHz en escala logarítmica.
let curvePoints = 96
let curveFreqs: [Double] = (0..<curvePoints).map { 20 * pow(1000, Double($0) / Double(curvePoints - 1)) }

/// Peso de cada punto para el auto-gain: igual por octava (ruido rosa) y ponderado K.
private let autoGainWeights: [Double] = {
    let s = Biquad.kShelf(fs: 48000), h = Biquad.kHighPass(fs: 48000)
    return curveFreqs.map { f in (f < 30 || f > 16000) ? 0 : s.magnitudeSquared(f, fs: 48000) * h.magnitudeSquared(f, fs: 48000) }
}()

struct Preset { let name: String; let gains: [Float] }

let presets: [Preset] = [
    Preset(name: "FLAT",    gains: Array(repeating: 0, count: 16)),
    Preset(name: "BASS",    gains: [6, 6, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    Preset(name: "TREBLE",  gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 6]),
    Preset(name: "VOCAL",   gains: [-4, -3, -2, -1, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, -1, -2]),
    Preset(name: "ROCK",    gains: [5, 5, 4, 2, 0, -1, -2, -2, -1, 0, 2, 3, 4, 5, 5, 5]),
    Preset(name: "DANCE",   gains: [6, 6, 5, 3, 1, 0, -1, -1, 0, 1, 2, 2, 3, 4, 5, 5]),
]

let filterDefs: [(id: String, name: String)] = [
    ("hp", "LOW CUT"), ("lp", "HIGH CUT"), ("loud", "LOUDNESS"), ("bass", "BASS +"),
    ("treble", "TREBLE +"), ("deess", "DE-ESS"), ("mono", "MONO"),
]

/// Estado recuperable por memorias y A/B.
struct Snapshot: Codable, Equatable {
    var gainsL: [Float]
    var gainsR: [Float]
    var preampDB: Float
    var filters: [String]
    var lowCutHz: Float
    var propQ: Bool
}

enum ChannelMode: Int {
    case link, left, right
    var label: String { ["LINK", "LEFT", "RIGHT"][rawValue] }
}

struct RunningApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let playing: Bool
}

@MainActor
final class EQModel: ObservableObject {
    @Published var gainsL: [Float] { didSet { changed() } }
    @Published var gainsR: [Float] { didSet { changed() } }
    @Published var preampDB: Float { didSet { changed() } }
    @Published var level: Float { didSet { changed() } }
    @Published var filters: Set<String> { didSet { changed() } }
    @Published var lowCutHz: Float { didSet { changed() } }
    @Published var limitDB: Float { didSet { changed() } }
    /// Ancho estéreo (mid/side): 0 = mono, 1 = original, 2 = lados al doble.
    @Published var width: Float { didSet { changed() } }
    @Published var propQ: Bool { didSet { changed() } }
    @Published var autoGain: Bool { didSet { changed() } }
    @Published var bypass = false { didSet { changed() } }
    @Published private(set) var rangeDB: Float { didSet { save() } }
    @Published private(set) var channelMode: ChannelMode = .link
    @Published var spectrumMode: Bool { didSet { save() } }
    @Published var showCurve: Bool { didSet { save() } }
    @Published private(set) var excludedApps: Set<String> { didSet { save() } }
    @Published private(set) var memories: [Snapshot?] { didSet { save() } }
    @Published var selectedBand = 8
    @Published private(set) var activePreset: String?
    @Published private(set) var activeMemory: Int?
    @Published var storeArmed = false
    @Published private(set) var abSlot = 0
    @Published var showOutputs = false
    @Published var showApps = false
    @Published private(set) var autoGainDB: Float = 0
    @Published private(set) var curveL: [Double] = []
    @Published private(set) var curveR: [Double] = []
    @Published private(set) var running = false
    @Published private(set) var status = "STANDBY"
    @Published private(set) var outputs: [OutputDevice] = []
    @Published private(set) var currentOutput = AudioObjectID(0)

    let engine = TapEngine()
    private var engineOutput = AudioObjectID(0)
    private var engineExcluded = Set<AudioObjectID>()
    private var abStore: [Snapshot?] = [nil, nil]
    private var lastEdited: ChannelMode = .left
    private var quiet = true
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        let legacy = (d.array(forKey: "gains16") as? [Float]).flatMap { $0.count == 16 ? $0 : nil }
        let flat = [Float](repeating: 0, count: 16)
        gainsL = (d.array(forKey: "gainsL") as? [Float]).flatMap { $0.count == 16 ? $0 : nil } ?? legacy ?? flat
        gainsR = (d.array(forKey: "gainsR") as? [Float]).flatMap { $0.count == 16 ? $0 : nil } ?? legacy ?? flat
        preampDB = d.float(forKey: "preampDB")
        level = d.object(forKey: "level") == nil ? 1 : d.float(forKey: "level")
        filters = Set(d.stringArray(forKey: "filters16") ?? [])
        lowCutHz = d.object(forKey: "lowCutHz") == nil ? 80 : d.float(forKey: "lowCutHz")
        limitDB = d.object(forKey: "limitDB") == nil ? -0.5 : d.float(forKey: "limitDB")
        width = d.object(forKey: "width") == nil ? 1 : min(max(d.float(forKey: "width"), 0), 2)
        propQ = d.bool(forKey: "propQ")
        autoGain = d.bool(forKey: "autoGain")
        rangeDB = d.float(forKey: "rangeDB") == 6 ? 6 : 12
        spectrumMode = d.object(forKey: "spectrumMode") == nil ? true : d.bool(forKey: "spectrumMode")
        showCurve = d.object(forKey: "showCurve") == nil ? true : d.bool(forKey: "showCurve")
        excludedApps = Set(d.stringArray(forKey: "excludedApps") ?? [])
        memories = (d.data(forKey: "memories")).flatMap { try? JSONDecoder().decode([Snapshot?].self, from: $0) } ?? [nil, nil, nil, nil]
        quiet = false

        engine.onSampleRateChange = { [weak self] in self?.restartIfRunning() }
        refreshDevices()
        listen(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.defaultOutputChanged() }
        listen(kAudioHardwarePropertyDevices) { [weak self] in self?.refreshDevices() }
        listen(kAudioHardwarePropertyProcessObjectList) { [weak self] in self?.processesChanged() }
        push()
        if d.bool(forKey: "wasRunning") { start() }
    }

    var outputName: String { outputs.first { $0.id == currentOutput }?.name ?? "SIN SALIDA" }
    var realOutputs: [OutputDevice] { outputs.filter { !$0.isVirtual } }
    var isSplit: Bool { gainsL != gainsR }

    private func listen(_ sel: AudioObjectPropertySelector, _ action: @escaping @MainActor () -> Void) {
        var a = propAddress(sel)
        AudioObjectAddPropertyListenerBlock(systemObject, &a, DispatchQueue.main) { _, _ in
            Task { @MainActor in action() }
        }
    }

    func refreshDevices() {
        let list = outputDevices()
        if list != outputs { outputs = list }
        let current = defaultOutputDevice()
        if current != currentOutput { currentOutput = current }
    }

    // MARK: Bandas y canales

    func gain(_ i: Int) -> Float { channelMode == .right ? gainsR[i] : gainsL[i] }

    func setGain(_ i: Int, _ v: Float) {
        let v = min(max(v, -rangeDB), rangeDB)
        batch {
            switch channelMode {
            case .link: gainsL[i] = v; gainsR[i] = v
            case .left: gainsL[i] = v; lastEdited = .left
            case .right: gainsR[i] = v; lastEdited = .right
            }
        }
        selectedBand = i
        activePreset = nil
        activeMemory = nil
    }

    /// LINK → LEFT → RIGHT → LINK. Al volver a LINK se copia el último canal editado a ambos.
    func cycleChannelMode() {
        switch channelMode {
        case .link: channelMode = .left
        case .left: channelMode = .right
        case .right:
            batch { if lastEdited == .right { gainsL = gainsR } else { gainsR = gainsL } }
            channelMode = .link
        }
    }

    /// Como en los EQ de hardware, el fader no se mueve: cambia cuántos dB representa su recorrido.
    func toggleRange() {
        let f: Float = rangeDB == 12 ? 0.5 : 2
        batch {
            gainsL = gainsL.map { ($0 * f * 2).rounded() / 2 }
            gainsR = gainsR.map { ($0 * f * 2).rounded() / 2 }
        }
        rangeDB = rangeDB == 12 ? 6 : 12
    }

    func applyPreset(_ p: Preset) {
        let g = p.gains.map { min(max($0, -rangeDB), rangeDB) }
        batch {
            switch channelMode {
            case .link: gainsL = g; gainsR = g
            case .left: gainsL = g
            case .right: gainsR = g
            }
        }
        activePreset = p.name
        activeMemory = nil
    }

    func toggleFilter(_ id: String) {
        if filters.contains(id) { filters.remove(id) } else { filters.insert(id) }
    }

    // MARK: Memorias y A/B

    private func snapshot() -> Snapshot {
        Snapshot(gainsL: gainsL, gainsR: gainsR, preampDB: preampDB, filters: filters.sorted(), lowCutHz: lowCutHz, propQ: propQ)
    }

    private func apply(_ s: Snapshot) {
        batch {
            gainsL = s.gainsL.map { min(max($0, -rangeDB), rangeDB) }
            gainsR = s.gainsR.map { min(max($0, -rangeDB), rangeDB) }
            preampDB = s.preampDB
            filters = Set(s.filters)
            lowCutHz = s.lowCutHz
            propQ = s.propQ
        }
        activePreset = nil
    }

    /// Con STORE armado guarda en la memoria; si no, la recupera.
    func pressMemory(_ i: Int) {
        if storeArmed {
            memories[i] = snapshot()
            storeArmed = false
            activeMemory = i
        } else if let s = memories[i] {
            apply(s)
            activeMemory = i
        }
    }

    func selectAB(_ slot: Int) {
        guard slot != abSlot else { return }
        abStore[abSlot] = snapshot()
        if let s = abStore[slot] { apply(s) }
        abSlot = slot
        activeMemory = nil
    }

    // MARK: Apps excluidas

    func runningApps() -> [RunningApp] {
        let procs = audioProcesses()
        let me = Bundle.main.bundleIdentifier
        var apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != me }
            .map { app -> RunningApp in
                let id = app.bundleIdentifier!
                return RunningApp(id: id, name: app.localizedName ?? id, icon: app.icon,
                                  playing: procs.contains { $0.isOutputting && $0.bundleID.hasPrefix(id) })
            }
        for id in excludedApps where !apps.contains(where: { $0.id == id }) {
            apps.append(RunningApp(id: id, name: id, icon: nil, playing: false))
        }
        return apps.sorted { ($0.playing ? 0 : 1, $0.name.lowercased()) < ($1.playing ? 0 : 1, $1.name.lowercased()) }
    }

    func setExcluded(_ id: String, _ on: Bool) {
        if on { excludedApps.insert(id) } else { excludedApps.remove(id) }
        if running { start() }
    }

    /// Un mismo programa puede sonar desde procesos ayudantes (p. ej. com.google.Chrome.helper).
    private func excludedObjects() -> Set<AudioObjectID> {
        guard !excludedApps.isEmpty else { return [] }
        return Set(audioProcesses()
            .filter { p in !p.bundleID.isEmpty && excludedApps.contains { p.bundleID.hasPrefix($0) } }
            .map(\.id))
    }

    private func processesChanged() {
        if running && !excludedApps.isEmpty && excludedObjects() != engineExcluded { start() }
    }

    // MARK: Cálculo y envío al DSP

    private func batch(_ f: () -> Void) {
        quiet = true
        f()
        quiet = false
        changed()
    }

    private func changed() {
        guard !quiet else { return }
        push()
        save()
    }

    private func stages(_ gains: [Float], fs: Double) -> [Biquad] {
        var s = (0..<16).map { i -> Biquad in
            let g = Double(gains[i])
            // Q proporcional: ancha con poca ganancia, estrecha con mucha. Q constante: 2/3 de octava fijo.
            let q = propQ ? 0.9 + 1.25 * min(abs(g), 12) / 12 : 2.15
            return .peaking(bandFreqs[i], q: q, gain: g, fs: fs)
        }
        let loud = filters.contains("loud")
        s.append(filters.contains("hp") ? .highPass(Double(lowCutHz), fs: fs) : .identity)
        s.append(filters.contains("lp") ? .lowPass(8000, fs: fs) : .identity)
        s.append(filters.contains("bass") || loud ? .lowShelf(100, gain: 6, fs: fs) : .identity)
        s.append(filters.contains("treble") || loud ? .highShelf(10000, gain: 4, fs: fs) : .identity)
        s.append(filters.contains("deess") ? .peaking(7000, q: 3, gain: -6, fs: fs) : .identity)
        return s
    }

    private func response(_ s: [Biquad], fs: Double) -> [Double] {
        curveFreqs.map { f in 10 * log10(max(s.reduce(1.0) { $0 * $1.magnitudeSquared(f, fs: fs) }, 1e-12)) }
    }

    private func push() {
        let fs = engine.sampleRate
        let sl = stages(gainsL, fs: fs), sr = stages(gainsR, fs: fs)
        curveL = response(sl, fs: fs)
        curveR = response(sr, fs: fs)
        if autoGain {
            var num = 0.0, den = 0.0
            for k in 0..<curvePoints where autoGainWeights[k] > 0 {
                num += autoGainWeights[k] * (pow(10, curveL[k] / 10) + pow(10, curveR[k] / 10)) / 2
                den += autoGainWeights[k]
            }
            autoGainDB = Float(min(max(-10 * log10(num / den), -24), 6))
        } else {
            autoGainDB = 0
        }
        engine.dsp.update(left: sl, right: sr, preampDB: preampDB, level: level, autoGainDB: autoGainDB,
                          limitDB: limitDB, mono: filters.contains("mono"), width: width, bypass: bypass)
    }

    private func save() {
        guard !quiet else { return }
        defaults.set(gainsL, forKey: "gainsL")
        defaults.set(gainsR, forKey: "gainsR")
        defaults.set(preampDB, forKey: "preampDB")
        defaults.set(level, forKey: "level")
        defaults.set(Array(filters), forKey: "filters16")
        defaults.set(lowCutHz, forKey: "lowCutHz")
        defaults.set(limitDB, forKey: "limitDB")
        defaults.set(width, forKey: "width")
        defaults.set(propQ, forKey: "propQ")
        defaults.set(autoGain, forKey: "autoGain")
        defaults.set(rangeDB, forKey: "rangeDB")
        defaults.set(spectrumMode, forKey: "spectrumMode")
        defaults.set(showCurve, forKey: "showCurve")
        defaults.set(Array(excludedApps), forKey: "excludedApps")
        defaults.set(try? JSONEncoder().encode(memories), forKey: "memories")
    }

    // MARK: Encendido y salida

    func togglePower() { running ? stop() : start() }

    func start() {
        refreshDevices()
        var out = defaultOutputDevice()
        // Si la salida del sistema quedó en un dispositivo virtual (p. ej. BlackHole), volver a uno real.
        if outputs.first(where: { $0.id == out })?.isVirtual ?? true {
            let last = defaults.string(forKey: "lastOutputUID")
            guard let real = realOutputs.first(where: { $0.uid == last }) ?? realOutputs.first else {
                status = "NO HAY SALIDA DE AUDIO REAL"
                return
            }
            setDefaultOutputDevice(real.id)
            out = real.id
        }
        do {
            let ex = excludedObjects()
            try engine.start(output: out, exclude: Array(ex))
            engineOutput = out
            engineExcluded = ex
            running = true
            push()   // la frecuencia de muestreo puede haber cambiado
            if let d = outputs.first(where: { $0.id == out }) { defaults.set(d.uid, forKey: "lastOutputUID") }
            status = "PROCESANDO · \(Int(engine.sampleRate)) HZ"
            defaults.set(true, forKey: "wasRunning")
        } catch {
            running = false
            engineOutput = 0
            status = "ERROR: " + error.localizedDescription.uppercased()
        }
        refreshDevices()
    }

    func stop() {
        engine.stop()
        running = false
        engineOutput = 0
        status = "STANDBY"
        defaults.set(false, forKey: "wasRunning")
    }

    func selectOutput(_ d: OutputDevice) {
        showOutputs = false
        setDefaultOutputDevice(d.id)
        refreshDevices()
        if running { start() }
    }

    private func restartIfRunning() { if running { start() } }

    private func defaultOutputChanged() {
        refreshDevices()
        if running && defaultOutputDevice() != engineOutput { start() }
    }
}

// MARK: - Medidores

@MainActor
final class MeterModel: ObservableObject {
    // VU (balística ~300 ms)
    @Published var left: Double = -0.04
    @Published var right: Double = -0.04
    @Published var signal = false
    // Analizador en unidades de LED (0…17) y su pico retenido
    @Published var levels = [Double](repeating: 0, count: 16)
    @Published var peaks = [Double](repeating: 0, count: 16)
    // Peak meter 0…1 (de -40 a 0 dBFS) y OVER
    @Published var peakL: Double = 0
    @Published var peakR: Double = 0
    @Published var overL = false
    @Published var overR = false
    // Loudness BS.1770
    @Published var lufsM = -Double.infinity
    @Published var lufsS = -Double.infinity
    @Published var lufsI = -Double.infinity
    // Pico máximo de los últimos 3 s y factor de cresta de 1 s
    @Published var peakHoldDB = -Double.infinity
    @Published var crestDB: Double = 0
    @Published var corr: Double = 0
    @Published var grDB: Double = 0

    private var timer: Timer?
    private var tick = 0
    private var holds = [Int](repeating: 0, count: 16)
    private var overHoldL = 0, overHoldR = 0
    private var lufsRead = 0
    private var recent: [Double] = []
    private var gated: [Double] = []
    private var peakWin: [Double] = []
    private var msWin: [Double] = []

    func attach(_ eq: EQModel) {
        guard timer == nil else { return }
        let debug = ProcessInfo.processInfo.environment["EQ_DEBUG"] != nil
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self, weak eq] _ in
            guard let self, let eq else { return }
            Task { @MainActor in self.step(eq, debug: debug) }
        }
    }

    func resetIntegrated() {
        gated.removeAll()
        lufsI = -.infinity
    }

    /// 0 VU = -12 dBFS RMS (música actual); la escala VU es lineal en voltaje.
    static func position(_ rms: Float) -> Double {
        let vu = 20 * log10(Double(max(rms, 1e-7))) + 12
        let p = (pow(10, vu / 20) - 0.1) / (pow(10, 0.15) - 0.1)
        return min(max(p, -0.04), 1.06)
    }

    private static func loudness(_ z: Double) -> Double { z > 0 ? -0.691 + 10 * log10(z) : -.infinity }

    private func step(_ eq: EQModel?, debug: Bool) {
        guard let eq else { return }
        let dsp = eq.engine.dsp
        let run = eq.running

        // VU
        left += ((run ? Self.position(dsp.rmsL) : -0.04) - left) * 0.3
        right += ((run ? Self.position(dsp.rmsR) : -0.04) - right) * 0.3

        // Analizador: 3 dB por LED, de -54 a -3 dBFS por banda
        var lv = levels, pk = peaks
        for b in 0..<16 {
            let db = 20 * log10(Double(max(dsp.spectrum[b], 1e-7)))
            let target = run ? min(max((db + 54) / 3, 0), 17) : 0
            lv[b] = target > lv[b] ? target : max(target, lv[b] - 0.3)
            if lv[b] >= pk[b] { pk[b] = lv[b]; holds[b] = 24 }
            else if holds[b] > 0 { holds[b] -= 1 }
            else { pk[b] = max(lv[b], pk[b] - 0.2) }
        }
        levels = lv; peaks = pk

        // Peak: subida instantánea, caída de 20 dB/s
        let pL = Double(dsp.peakL), pR = Double(dsp.peakR)
        dsp.peakL = 0; dsp.peakR = 0
        func strip(_ p: Double) -> Double { min(max((20 * log10(max(p, 1e-7)) + 40) / 40, 0), 1) }
        peakL = run ? max(strip(pL), peakL - 0.0167) : 0
        peakR = run ? max(strip(pR), peakR - 0.0167) : 0
        if dsp.overL { overHoldL = 60; dsp.overL = false }
        if dsp.overR { overHoldR = 60; dsp.overR = false }
        overHoldL = max(0, overHoldL - 1); overHoldR = max(0, overHoldR - 1)
        overL = run && overHoldL > 0
        overR = run && overHoldR > 0

        // Reducción del limitador
        let g = Double(dsp.grMin)
        dsp.grMin = 1
        grDB = run ? min(0, min(20 * log10(max(g, 1e-4)), grDB + 0.5)) : 0

        // Correlación de fase
        let lr = dsp.corrLR, ll = dsp.corrLL, rr = dsp.corrRR
        dsp.corrLR = 0; dsp.corrLL = 0; dsp.corrRR = 0
        let c = ll * rr > 1e-12 ? lr / sqrt(ll * rr) : 0
        corr += ((run ? c : 0) - corr) * 0.15

        // Pico retenido y factor de cresta
        peakWin.append(max(pL, pR)); if peakWin.count > 90 { peakWin.removeFirst() }
        msWin.append(Double(dsp.rmsL * dsp.rmsL + dsp.rmsR * dsp.rmsR) / 2); if msWin.count > 30 { msWin.removeFirst() }
        let maxPeak = peakWin.max() ?? 0
        peakHoldDB = run && maxPeak > 1e-6 ? 20 * log10(maxPeak) : -.infinity
        let ms = msWin.reduce(0, +) / Double(max(msWin.count, 1))
        let pk1 = peakWin.suffix(30).max() ?? 0
        crestDB = run && ms > 1e-10 && pk1 > 0 ? 20 * log10(pk1 / sqrt(ms)) : 0

        // Loudness: momentáneo (400 ms), corto (3 s) e integrado con compuerta
        let count = dsp.lufsBlockCount
        if count - lufsRead > DSP.lufsRing { lufsRead = count - DSP.lufsRing }
        while lufsRead < count {
            recent.append(dsp.lufsBlocks[lufsRead % DSP.lufsRing])
            if recent.count > 30 { recent.removeFirst() }
            if recent.count >= 4 && gated.count < 200_000 { gated.append(recent.suffix(4).reduce(0, +) / 4) }
            lufsRead += 1
        }
        if run && recent.count >= 4 {
            lufsM = Self.loudness(recent.suffix(4).reduce(0, +) / 4)
            lufsS = Self.loudness(recent.reduce(0, +) / Double(recent.count))
        } else if !run {
            recent.removeAll()
            lufsM = -.infinity; lufsS = -.infinity
        }
        if tick % 10 == 0 { lufsI = integrated() }

        let s = run && dsp.inputPeak > 0.0005
        if s != signal { signal = s }
        tick += 1
        if debug && tick % 30 == 0 {
            let line = "running=\(run) callbacks=\(dsp.callbacks) inStreams=\(eq.engine.inputStreamCount) inPeak=\(dsp.inputPeak) rmsL=\(dsp.rmsL) lufsM=\(lufsM) corr=\(corr) gr=\(grDB) fs=\(eq.engine.sampleRate) out=\(eq.outputName)\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
    }

    private func integrated() -> Double {
        let absGate = pow(10, (-70 + 0.691) / 10)
        let a = gated.filter { $0 > absGate }
        guard !a.isEmpty else { return -.infinity }
        let rel = pow(10, (Self.loudness(a.reduce(0, +) / Double(a.count)) - 10 + 0.691) / 10)
        let b = a.filter { $0 > rel }
        return b.isEmpty ? -.infinity : Self.loudness(b.reduce(0, +) / Double(b.count))
    }
}

// MARK: - Reproductor

/// Lo que se sabe de la app de música activa.
struct MediaInfo: Equatable {
    var app: String
    var title: String
    var artist: String
    var album: String
    /// Posición (s) en el momento `stamp`; la interfaz la hace avanzar mientras `playing`.
    var position: Double
    var duration: Double
    var playing: Bool
    var volume: Double?
    var stamp = Date()
    /// Bundle ID de la app (para elegir cómo controlarla).
    var bundle = ""
    /// `false` si la fuente no da la posición (sólo se sabe qué suena): la interfaz muestra "--:--".
    var timed = true
    /// Carátula de la canción, si la fuente la da.
    var artwork: NSImage? = nil
}

enum MediaCommand { case previous, toggle, next }

/// Reproductor de música activo (o ninguno).
///
/// Sólo cuentan los reproductores: apps conocidas (Spotify, Música, TIDAL, Deezer, VLC…) o las que
/// declaran la categoría "Música" en su Info.plist. Navegadores, videollamadas, juegos o sonidos del
/// sistema no aparecen aunque tengan audio.
///
/// Fuentes, de más a menos completa:
/// 1. AppleScript de Spotify y Música: canción, posición exacta, duración y volumen.
/// 2. MediaRemote (lo que macOS muestra en el Centro de control). Desde macOS 15.4 sólo responde a
///    procesos de Apple, así que se lee a través de /usr/bin/perl (ver MediaRemoteHelper.m); si ese
///    puente no funciona se consulta directamente, lo que sirve en versiones anteriores.
/// 3. Notificaciones distribuidas de Spotify y Música (sin permisos).
/// 4. Reproductores con audio de salida activo (Core Audio), con el título deducido de su ventana.
///
/// Si suenan varios se mantiene el que ya se mostraba; si ninguno suena, queda el último en pausa
/// mientras siga abierto.
///
/// `MAD_DEMO_PLAYER=1` muestra una pista de ejemplo.
@MainActor
final class NowPlaying: ObservableObject {
    @Published private(set) var info: MediaInfo?

    private var scripted: [String: MediaInfo] = [:]  // AppleScript, por bundle
    private var rich: [String: MediaInfo] = [:]      // notificaciones, por bundle
    private var remote: MediaInfo?                   // MediaRemote
    private var heard: MediaInfo?                    // último reproductor detectado por su audio
    private var scripts: [String: NSAppleScript] = [:]
    private var denied: Set<String> = []             // apps sin permiso de Automatización
    private var playerCache: [String: Bool] = [:]
    private var timer: Timer?
    private var askedAccessibility = false
    private var observers: [NSObjectProtocol] = []
    private let demo = ProcessInfo.processInfo.environment["MAD_DEMO_PLAYER"] != nil

    private var helper: Process?
    private var helperBuffer = Data()
    private var helperFailures = 0
    private var helperAlive = false
    private var remoteArt: (key: String, image: NSImage?) = ("", nil)  // última carátula de MediaRemote
    private var artCache: [String: NSImage] = [:]   // Spotify (por URL) y Música (por canción)
    private var artTried: Set<String> = []
    private var helperInput: FileHandle?            // comandos al puente, uno por línea

    private static let spotify = "com.spotify.client"
    private static let music = "com.apple.Music"

    /// Reproductores conocidos (además de los que se declaran de la categoría Música).
    private static let knownPlayers: Set<String> = [
        spotify, music, "com.apple.podcasts", "com.tidal.desktop", "com.deezer.deezer-desktop",
        "com.amazon.music", "com.qobuz.QobuzDesktop", "org.videolan.vlc", "com.coppertino.Vox",
        "com.swinsian.Swinsian", "co.brushedtype.doppler-macos", "tv.plex.plexamp", "com.roon.Roon",
        "com.audirvana.Audirvana-Studio", "com.audirvana.Audirvana", "sh.cider.genten.mac",
        "sh.cider.electron", "com.github.th-ch.youtube-music", "app.ytmdesktop.ytmdesktop",
        "com.foobar2000.mac", "com.pandora.desktop", "com.soundcloud.desktop",
        "com.netease.163music", "com.tencent.QQMusicMac",
    ]

    init() {
        if demo {
            info = MediaInfo(app: "Spotify", title: "Midnight City", artist: "M83",
                             album: "Hurry Up, We're Dreaming · 2011", position: 108, duration: 222,
                             playing: true, volume: 0.68, bundle: Self.spotify)
            return
        }
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, "com.spotify.client.PlaybackStateChanged", app: "Spotify", bundle: Self.spotify)
        observe(dnc, "com.apple.Music.playerInfo", app: "Música", bundle: Self.music)
        observe(dnc, "com.apple.iTunes.playerInfo", app: "Música", bundle: Self.music)
        // Escribir al puente cuando acaba de cerrarse no debe matar la app.
        signal(SIGPIPE, SIG_IGN)
        startHelper()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
        helper?.terminate()
        for o in observers { DistributedNotificationCenter.default().removeObserver(o) }
    }

    // MARK: Qué es un reproductor

    private func isPlayer(_ bundle: String) -> Bool {
        guard !bundle.isEmpty, bundle != Bundle.main.bundleIdentifier else { return false }
        if let known = playerCache[bundle] { return known }
        var ok = Self.knownPlayers.contains(bundle)
        if !ok, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle),
           let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            ok = category == "public.app-category.music"
        }
        playerCache[bundle] = ok
        return ok
    }

    private func running(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    /// App regular a la que pertenece un proceso de audio. Las apps Electron (Tidal, Spotify…) y los
    /// navegadores suenan desde procesos auxiliares con ID tipo `com.tidal.desktop.helper.Renderer`:
    /// se va recortando el ID hasta dar con la app principal.
    private func owner(of bundleID: String) -> NSRunningApplication? {
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            let id = parts.joined(separator: ".")
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .first(where: { $0.activationPolicy == .regular }) { return app }
            parts.removeLast()
        }
        return nil
    }

    private func runningApp(pid: pid_t) -> NSRunningApplication? {
        guard pid > 0, let a = NSRunningApplication(processIdentifier: pid) else { return nil }
        if a.activationPolicy == .regular { return a }
        return a.bundleIdentifier.flatMap(owner(of:)) ?? a
    }

    // MARK: Elección

    private func refresh() {
        pollScripts()
        if !helperAlive { queryRemote() }
        recompute()
    }

    private func recompute() {
        rich = rich.filter { running($0.key) }
        var list: [MediaInfo] = []
        for b in [Self.spotify, Self.music] {
            if let s = scripted[b] { list.append(s) } else if let r = rich[b] { list.append(r) }
        }
        if let m = remote, !list.contains(where: { $0.bundle == m.bundle }) { list.append(m) }

        if !list.contains(where: \.playing) {
            // Ninguna fuente con metadatos dice que suene algo: se mira qué reproductor tiene audio.
            if let a = audioSource(excluding: Set(list.map(\.bundle))) { heard = a }
            else if var h = heard, running(h.bundle) { h.playing = false; heard = h }
            else { heard = nil }
            if let h = heard, !list.contains(where: { $0.bundle == h.bundle }) { list.append(h) }
        } else {
            heard = nil
        }

        let current = info?.bundle
        let pick = list.first { $0.playing && $0.bundle == current }
            ?? list.first { $0.playing }
            ?? list.first { $0.bundle == current }
            ?? list.first
        if pick != info { info = pick }
    }

    // MARK: AppleScript (Spotify y Música)

    private static let scriptSources: [String: String] = [
        spotify: """
        if application "Spotify" is running then
          with timeout of 2 seconds
            tell application "Spotify"
              set s to player state as string
              if s is "stopped" then return {s}
              set t to current track
              return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, sound volume, artwork url of t}
            end tell
          end timeout
        end if
        return {"stopped"}
        """,
        music: """
        if application "Music" is running then
          with timeout of 2 seconds
            tell application "Music"
              set s to player state as string
              if s is "stopped" then return {s}
              set t to current track
              return {s, name of t, artist of t, album of t, duration of t, player position, sound volume}
            end tell
          end timeout
        end if
        return {"stopped"}
        """,
    ]

    /// Sólo se consulta una app si está abierta (si no, AppleScript la abriría) y si no se ha negado
    /// el permiso de Automatización.
    private func pollScripts() {
        for (bundle, source) in Self.scriptSources {
            guard !denied.contains(bundle), running(bundle) else { scripted[bundle] = nil; continue }
            let script = scripts[bundle] ?? NSAppleScript(source: source)
            scripts[bundle] = script
            var err: NSDictionary?
            guard let r = script?.executeAndReturnError(&err), err == nil else {
                if (err?[NSAppleScript.errorNumber] as? Int) == -1743 { denied.insert(bundle) }
                scripted[bundle] = nil
                continue
            }
            scripted[bundle] = scriptInfo(r, bundle: bundle)
        }
    }

    private func scriptInfo(_ r: NSAppleEventDescriptor, bundle: String) -> MediaInfo? {
        guard r.numberOfItems >= 7, let state = r.atIndex(1)?.stringValue, state != "stopped" else { return nil }
        func s(_ k: Int) -> String { r.atIndex(k)?.stringValue ?? "" }
        func n(_ k: Int) -> Double { r.atIndex(k)?.doubleValue ?? 0 }
        let title = s(2)
        guard !title.isEmpty else { return nil }
        var i = MediaInfo(app: bundle == Self.spotify ? "Spotify" : "Música", title: title,
                          artist: s(3), album: s(4), position: n(6), duration: n(5),
                          playing: state == "playing", volume: min(1, max(0, n(7) / 100)), bundle: bundle)
        i.artwork = bundle == Self.spotify ? spotifyArtwork(s(8)) : musicArtwork("\(title)|\(i.artist)|\(i.album)")
        return i
    }

    // MARK: Carátulas

    private func storeArt(_ image: NSImage, _ key: String) {
        if artCache.count > 40 { artCache.removeAll(); artTried.removeAll() }
        artCache[key] = image
    }

    /// Spotify da una URL (i.scdn.co); se descarga una vez y queda en caché.
    private func spotifyArtwork(_ link: String) -> NSImage? {
        guard !link.isEmpty, let url = URL(string: link) else { return nil }
        if let img = artCache[link] { return img }
        guard !artTried.contains(link) else { return nil }
        artTried.insert(link)
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }
            Task { @MainActor in
                guard let self, let img = NSImage(data: data) else { return }
                self.storeArt(img, link)
                self.refresh()
            }
        }.resume()
        return nil
    }

    private static let musicArtworkScript = """
    if application "Music" is running then
      with timeout of 2 seconds
        tell application "Music" to return data of artwork 1 of current track
      end timeout
    end if
    """

    /// Música da la imagen en sí; se pide una sola vez por canción.
    private func musicArtwork(_ key: String) -> NSImage? {
        if let img = artCache[key] { return img }
        guard !artTried.contains(key) else { return nil }
        artTried.insert(key)
        var err: NSDictionary?
        guard let d = NSAppleScript(source: Self.musicArtworkScript)?.executeAndReturnError(&err), err == nil,
              let img = NSImage(data: d.data) else { return nil }
        storeArt(img, key)
        return img
    }

    // MARK: Notificaciones (Spotify y Música)

    private func observe(_ dnc: DistributedNotificationCenter, _ name: String, app: String, bundle: String) {
        let o = dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] n in
            let u = n.userInfo ?? [:]
            func num(_ k: String) -> Double? { (u[k] as? NSNumber)?.doubleValue }
            let state = (u["Player State"] as? String ?? "").lowercased()
            let title = u["Name"] as? String ?? ""
            // Spotify da la duración en ms ("Duration"); Música, en "Total Time" (ms) y sin posición.
            let i = MediaInfo(app: app, title: title,
                              artist: u["Artist"] as? String ?? "",
                              album: u["Album"] as? String ?? "",
                              position: num("Playback Position") ?? 0,
                              duration: (num("Duration") ?? num("Total Time") ?? 0) / 1000,
                              playing: state == "playing",
                              volume: nil, bundle: bundle,
                              timed: num("Playback Position") != nil)
            let keep = state != "stopped" && !title.isEmpty
            Task { @MainActor in
                guard let self else { return }
                self.rich[bundle] = keep ? i : nil
                self.refresh()
            }
        }
        observers.append(o)
    }

    // MARK: Audio de salida (último recurso)

    /// Título de la ventana de la app ("Canción - Artista"). Se prueba primero con Accesibilidad
    /// (permiso más acotado) y, si ya está concedido, con la lista de ventanas (Grabación de pantalla).
    private func windowTitle(pid: pid_t) -> String? {
        axTitle(pid: pid) ?? cgTitle(pid: pid)
    }

    private func axTitle(pid: pid_t) -> String? {
        if !AXIsProcessTrusted() {
            if !askedAccessibility {
                askedAccessibility = true
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for w in windows {
            var t: CFTypeRef?
            if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success,
               let title = t as? String, title.contains(" - ") { return title }
        }
        return nil
    }

    private func cgTitle(pid: pid_t) -> String? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
            if let t = w[kCGWindowName as String] as? String, t.contains(" - ") { return t }
        }
        return nil
    }

    /// Reproductor con salida de audio activa; con canción sólo si se puede deducir de su ventana.
    /// No se conoce la posición, así que la interfaz no inventa un tiempo.
    private func audioSource(excluding skip: Set<String>) -> MediaInfo? {
        for p in audioProcesses() where p.isOutputting {
            guard let app = owner(of: p.bundleID), let bundle = app.bundleIdentifier,
                  !skip.contains(bundle), isPlayer(bundle), let name = app.localizedName else { continue }
            var title = "Reproduciendo", artist = ""
            if let t = windowTitle(pid: app.processIdentifier),
               let r = t.range(of: " - ", options: .backwards) {
                title = String(t[..<r.lowerBound]); artist = String(t[r.upperBound...])
            }
            return MediaInfo(app: name, title: title, artist: artist, album: "",
                             position: 0, duration: 0, playing: true, volume: nil,
                             bundle: bundle, timed: false)
        }
        return nil
    }

    // MARK: MediaRemote

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let perlLoader = """
    use DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or exit 4;
    my $s = DynaLoader::dl_find_symbol($h, "mad_mediaremote") or exit 5;
    DynaLoader::dl_install_xsub("main::mad_mediaremote", $s);
    mad_mediaremote();
    """

    private static var helperLibrary: URL? {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("MADMediaRemote.dylib"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }


    /// Lanza el puente (una línea JSON por segundo). Si se cae, se reintenta unas cuantas veces.
    private func startHelper() {
        guard helper == nil, helperFailures < 5, let lib = Self.helperLibrary else { return }
        let p = Process()
        p.executableURL = Self.perl
        p.arguments = ["-e", Self.perlLoader, lib.path]
        p.standardError = FileHandle.nullDevice
        let out = Pipe(), input = Pipe()
        p.standardOutput = out
        p.standardInput = input
        helperInput = input.fileHandleForWriting
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            Task { @MainActor in self?.helperData(data) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.helperExited() }
        }
        do { try p.run(); helper = p } catch { helperFailures += 1 }
    }

    private func helperExited() {
        helper = nil
        helperInput = nil
        helperAlive = false
        helperBuffer.removeAll()
        helperFailures += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(3 * helperFailures)) { [weak self] in
            Task { @MainActor in self?.startHelper() }
        }
    }

    private func helperData(_ data: Data) {
        helperBuffer.append(data)
        while let nl = helperBuffer.firstIndex(of: 0x0A) {
            let line = Data(helperBuffer[helperBuffer.startIndex..<nl])
            helperBuffer.removeSubrange(helperBuffer.startIndex...nl)
            helperAlive = true
            helperFailures = 0
            let obj = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed])
            remote = (obj as? [String: Any]).flatMap(remoteInfo)
            recompute()
        }
    }

    /// Convierte lo leído de MediaRemote; descarta lo que no venga de un reproductor.
    private func remoteInfo(_ d: [String: Any]) -> MediaInfo? {
        func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        // La carátula sólo llega cuando cambia (en base64 desde el puente, o en bruto en la consulta directa).
        let artKey = d["artworkKey"] as? String ?? ""
        if artKey != remoteArt.key {
            if let b64 = d["artwork"] as? String {
                remoteArt = (artKey, Data(base64Encoded: b64).flatMap(NSImage.init(data:)))
            } else if let raw = d["artworkData"] as? Data {
                remoteArt = (artKey, NSImage(data: raw))
            } else if d["artworkData"] != nil || d["artwork"] != nil {
                remoteArt = (artKey, nil)
            }
        }
        let title = d["title"] as? String ?? ""
        guard !title.isEmpty, let app = runningApp(pid: pid_t(num("pid"))),
              let bundle = app.bundleIdentifier, isPlayer(bundle) else { return nil }
        var i = MediaInfo(app: app.localizedName ?? "Reproductor", title: title,
                          artist: d["artist"] as? String ?? "", album: d["album"] as? String ?? "",
                          position: num("elapsed"), duration: num("duration"),
                          playing: (d["playing"] as? Bool ?? false) || num("rate") > 0,
                          volume: nil, bundle: bundle)
        if artKey == remoteArt.key { i.artwork = remoteArt.image }
        // La posición corresponde al instante en que el reproductor la informó, no al de la lectura.
        let ts = num("timestamp")
        if ts > 0 { i.stamp = Date(timeIntervalSince1970: ts) }
        return i
    }

    // Consulta directa (sirve hasta macOS 15.3, o si el puente no arranca).
    private typealias InfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias PidFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void

    private static let mediaRemote: (info: InfoFn, pid: PidFn)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let a = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"),
              let b = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID") else { return nil }
        return (unsafeBitCast(a, to: InfoFn.self), unsafeBitCast(b, to: PidFn.self))
    }()

    private func queryRemote() {
        guard let mr = Self.mediaRemote else { return }
        mr.pid(.main) { [weak self] pid in
            mr.info(.main) { dict in
                let d = (dict as NSDictionary?) as? [String: Any] ?? [:]
                func n(_ k: String) -> NSNumber { d[k] as? NSNumber ?? NSNumber(value: 0) }
                let ts = (d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)?.timeIntervalSince1970 ?? 0
                let art = d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                let artKey = ["Title", "Artist", "Album"]
                    .map { d["kMRMediaRemoteNowPlayingInfo\($0)"] as? String ?? "" }
                    .joined(separator: "|") + "|\(art?.count ?? 0)"
                let flat: [String: Any] = [
                    "artworkKey": artKey,
                    "artworkData": art ?? NSNull(),
                    "pid": NSNumber(value: pid),
                    "title": d["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "",
                    "artist": d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                    "album": d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                    "duration": n("kMRMediaRemoteNowPlayingInfoDuration"),
                    "elapsed": n("kMRMediaRemoteNowPlayingInfoElapsedTime"),
                    "rate": n("kMRMediaRemoteNowPlayingInfoPlaybackRate"),
                    "timestamp": NSNumber(value: ts),
                ]
                Task { @MainActor in
                    guard let self, !self.helperAlive else { return }
                    self.remote = self.remoteInfo(flat)
                    self.recompute()
                }
            }
        }
    }

    /// Envía un comando de MediaRemote a la app que macOS considera activa (la del Centro de control).
    private func sendRemote(_ c: MediaCommand) -> Bool {
        guard helperAlive, let input = helperInput else { return false }
        let code: Int
        switch c {
        case .toggle: code = 2
        case .next: code = 4
        case .previous: code = 5
        }
        do { try input.write(contentsOf: Data("\(code)\n".utf8)) } catch { return false }
        return true
    }

    // MARK: Controles

    func command(_ c: MediaCommand) {
        guard !demo else { return }
        let bundle = info?.bundle ?? ""
        if (bundle == Self.spotify || bundle == Self.music) && !denied.contains(bundle) {
            let verb: String
            switch c {
            case .previous: verb = "previous track"
            case .toggle: verb = "playpause"
            case .next: verb = "next track"
            }
            let target = bundle == Self.spotify ? "Spotify" : "Music"
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"\(target)\" to \(verb)")?.executeAndReturnError(&err)
            if err == nil { settle(c); return }
        }
        // El resto (TIDAL, Deezer…), por MediaRemote.
        if sendRemote(c) { settle(c); return }
        // Último recurso: tecla multimedia del sistema.
        switch c {
        case .previous: Self.mediaKey(18)
        case .toggle: Self.mediaKey(16)
        case .next: Self.mediaKey(17)
        }
        settle(c)
    }

    /// Refleja el cambio de inmediato; la siguiente lectura lo confirma.
    private func settle(_ c: MediaCommand) {
        if c == .toggle, var i = info {
            i.position = i.position + (i.playing ? Date().timeIntervalSince(i.stamp) : 0)
            i.stamp = Date()
            i.playing.toggle()
            info = i
            if rich[i.bundle] != nil { rich[i.bundle] = i }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    private static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let flags = down ? 0xA00 : 0xB00
            NSEvent.otherEvent(with: .systemDefined, location: .zero,
                               modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                               timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                               data1: (key << 16) | flags, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
