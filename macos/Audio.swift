import Foundation
import CoreAudio
import AudioToolbox

// MARK: - Utilidades Core Audio

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func propAddress(_ sel: AudioObjectPropertySelector,
                 _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readValue<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                  _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ fallback: T) -> T {
    var a = propAddress(sel, scope)
    var v = fallback
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : fallback
}

func readString(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
    var a = propAddress(sel)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var s: Unmanaged<CFString>? = nil
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
    return s.takeRetainedValue() as String
}

func readIDs(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var a = propAddress(sel, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isVirtual: Bool
}

func outputDevices() -> [OutputDevice] {
    readIDs(systemObject, kAudioHardwarePropertyDevices).compactMap { id in
        guard !readIDs(id, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput).isEmpty,
              let uid = readString(id, kAudioDevicePropertyDeviceUID),
              let name = readString(id, kAudioObjectPropertyName) else { return nil }
        let transport = readValue(id, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0))
        if transport == kAudioDeviceTransportTypeAggregate { return nil }
        return OutputDevice(id: id, uid: uid, name: name, isVirtual: transport == kAudioDeviceTransportTypeVirtual)
    }
}

func defaultOutputDevice() -> AudioObjectID {
    readValue(systemObject, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0))
}

func setDefaultOutputDevice(_ id: AudioObjectID) {
    var a = propAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var v = id
    AudioObjectSetPropertyData(systemObject, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &v)
}

func ownProcessObject() -> AudioObjectID {
    var a = propAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pid = getpid()
    var obj = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(systemObject, &a, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj)
    return obj
}

/// Procesos que usan audio (incluye ayudantes como los de Chrome o Teams).
struct AudioProcess {
    let id: AudioObjectID
    let bundleID: String
    let isOutputting: Bool
}

func audioProcesses() -> [AudioProcess] {
    readIDs(systemObject, kAudioHardwarePropertyProcessObjectList).map { id in
        AudioProcess(id: id,
                     bundleID: readString(id, kAudioProcessPropertyBundleID) ?? "",
                     isOutputting: readValue(id, kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal, UInt32(0)) != 0)
    }
}

// MARK: - Filtros biquad (RBJ Audio EQ Cookbook)

struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    static let identity = Biquad()

    private static func make(_ b0: Double, _ b1: Double, _ b2: Double,
                             _ a0: Double, _ a1: Double, _ a2: Double) -> Biquad {
        Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    private static func w0(_ f: Double, _ fs: Double) -> Double { 2 * .pi * min(f, fs * 0.45) / fs }

    static func peaking(_ f: Double, q: Double, gain: Double, fs: Double) -> Biquad {
        if gain == 0 { return .identity }
        let A = pow(10, gain / 40), w = w0(f, fs), al = sin(w) / (2 * q), c = cos(w)
        return make(1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A)
    }

    static func lowShelf(_ f: Double, gain: Double, fs: Double) -> Biquad {
        let A = pow(10, gain / 40), w = w0(f, fs), c = cos(w), al = sin(w) / 2 * sqrt(2), s = 2 * sqrt(A) * al
        return make(A * ((A + 1) - (A - 1) * c + s), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - s),
                    (A + 1) + (A - 1) * c + s, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - s)
    }

    static func highShelf(_ f: Double, gain: Double, fs: Double) -> Biquad {
        let A = pow(10, gain / 40), w = w0(f, fs), c = cos(w), al = sin(w) / 2 * sqrt(2), s = 2 * sqrt(A) * al
        return make(A * ((A + 1) + (A - 1) * c + s), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - s),
                    (A + 1) - (A - 1) * c + s, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - s)
    }

    static func highPass(_ f: Double, fs: Double) -> Biquad {
        let w = w0(f, fs), c = cos(w), al = sin(w) / (2 * 0.7071)
        return make((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
    }

    /// Pasa-banda con 0 dB en el pico, para el analizador.
    static func bandPass(_ f: Double, q: Double, fs: Double) -> Biquad {
        let w = w0(f, fs), c = cos(w), al = sin(w) / (2 * q)
        return make(al, 0, -al, 1 + al, -2 * c, 1 - al)
    }

    static func lowPass(_ f: Double, fs: Double) -> Biquad {
        let w = w0(f, fs), c = cos(w), al = sin(w) / (2 * 0.7071)
        return make((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)
    }

    /// Ponderación K de ITU-R BS.1770 (las mismas fórmulas que libebur128, válidas a cualquier frecuencia).
    static func kShelf(fs: Double) -> Biquad {
        let f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196
        let K = tan(.pi * f0 / fs), Vh = pow(10, G / 20), Vb = pow(Vh, 0.4996667741545416)
        let a0 = 1 + K / Q + K * K
        return Biquad(b0: (Vh + Vb * K / Q + K * K) / a0, b1: 2 * (K * K - Vh) / a0, b2: (Vh - Vb * K / Q + K * K) / a0,
                      a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0)
    }

    static func kHighPass(fs: Double) -> Biquad {
        let f0 = 38.13547087602444, Q = 0.5003270373238773
        let K = tan(.pi * f0 / fs), a0 = 1 + K / Q + K * K
        return Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0)
    }

    func magnitudeSquared(_ f: Double, fs: Double) -> Double {
        let w = 2 * .pi * f / fs, c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2)
        let dr = 1 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2)
        return (nr * nr + ni * ni) / max(dr * dr + di * di, 1e-30)
    }
}

// MARK: - Procesador en tiempo real

/// Todo lo que toca el hilo de audio vive en memoria fija: sin asignaciones ni bloqueos que esperen.
/// Los medidores "desde la última lectura" los consume y reinicia la interfaz.
final class DSP: @unchecked Sendable {
    static let stages = 21   // 16 bandas + low cut, high cut, shelf graves, shelf agudos, de-esser
    static let bands = 16
    static let scopeSize = 1024
    static let lufsRing = 64

    private let coefsL = UnsafeMutablePointer<Biquad>.allocate(capacity: stages)
    private let coefsR = UnsafeMutablePointer<Biquad>.allocate(capacity: stages)
    private let pendingL = UnsafeMutablePointer<Biquad>.allocate(capacity: stages)
    private let pendingR = UnsafeMutablePointer<Biquad>.allocate(capacity: stages)
    private let state = UnsafeMutablePointer<Double>.allocate(capacity: stages * 4)
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var dirty = false
    private var preamp: Float = 1, level: Float = 1, autoGain: Float = 1, limit: Float = 0.94
    private var mono = false, bypass = false
    private var pPreamp: Float = 1, pLevel: Float = 1, pAutoGain: Float = 1, pLimit: Float = 0.94
    private var pMono = false, pBypass = false
    private var agSmooth: Float = 1, agCoef: Float = 0.0005
    private var limGain: Float = 1, limRelease: Float = 0.9998
    private var fade: Float = 0, fadeStep: Float = 0

    // Analizador: 16 pasa-banda sobre la salida en mono
    private let anaCoefs = UnsafeMutablePointer<Biquad>.allocate(capacity: bands)
    private let anaState = UnsafeMutablePointer<Double>.allocate(capacity: bands * 2)
    private let anaSum = UnsafeMutablePointer<Float>.allocate(capacity: bands)
    /// RMS por banda del último bloque.
    let spectrum = UnsafeMutablePointer<Float>.allocate(capacity: bands)

    // Loudness (BS.1770): energía ponderada K de bloques de 100 ms
    private var kShelf = Biquad.identity, kHP = Biquad.identity
    private let kState = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    private var kSum = 0.0, kCount = 0, kBlockLen = 4800
    let lufsBlocks = UnsafeMutablePointer<Double>.allocate(capacity: lufsRing)
    private(set) var lufsBlockCount = 0

    // Goniómetro: últimos puntos (lado, medio)
    let scopeX = UnsafeMutablePointer<Float>.allocate(capacity: scopeSize)
    let scopeY = UnsafeMutablePointer<Float>.allocate(capacity: scopeSize)
    private(set) var scopeIndex = 0
    private var scopeSkip = false

    // Medidores
    var rmsL: Float = 0, rmsR: Float = 0, inputPeak: Float = 0
    var peakL: Float = 0, peakR: Float = 0
    var overL = false, overR = false
    var grMin: Float = 1
    var corrLR = 0.0, corrLL = 0.0, corrRR = 0.0
    var callbacks = 0, inputStreamsSeen = 0

    init() {
        coefsL.initialize(repeating: .identity, count: DSP.stages)
        coefsR.initialize(repeating: .identity, count: DSP.stages)
        pendingL.initialize(repeating: .identity, count: DSP.stages)
        pendingR.initialize(repeating: .identity, count: DSP.stages)
        state.initialize(repeating: 0, count: DSP.stages * 4)
        lock.initialize(to: os_unfair_lock())
        anaCoefs.initialize(repeating: .identity, count: DSP.bands)
        anaState.initialize(repeating: 0, count: DSP.bands * 2)
        anaSum.initialize(repeating: 0, count: DSP.bands)
        spectrum.initialize(repeating: 0, count: DSP.bands)
        kState.initialize(repeating: 0, count: 8)
        lufsBlocks.initialize(repeating: 0, count: DSP.lufsRing)
        scopeX.initialize(repeating: 0, count: DSP.scopeSize)
        scopeY.initialize(repeating: 0, count: DSP.scopeSize)
    }

    /// Llamar antes de arrancar: reinicia estados y prepara un fundido de entrada de 300 ms.
    func prepare(sampleRate fs: Double) {
        os_unfair_lock_lock(lock)
        state.update(repeating: 0, count: DSP.stages * 4)
        fade = 0
        fadeStep = Float(1 / (fs * 0.3))
        agCoef = Float(1 - exp(-1 / (fs * 0.05)))
        limGain = 1
        limRelease = Float(exp(-1 / (fs * 0.15)))
        for b in 0..<DSP.bands { anaCoefs[b] = .bandPass(bandFreqs[b], q: 2.15, fs: fs) }
        anaState.update(repeating: 0, count: DSP.bands * 2)
        anaSum.update(repeating: 0, count: DSP.bands)
        kShelf = .kShelf(fs: fs); kHP = .kHighPass(fs: fs)
        kState.update(repeating: 0, count: 8)
        kSum = 0; kCount = 0; kBlockLen = Int(fs * 0.1)
        os_unfair_lock_unlock(lock)
    }

    func update(left: [Biquad], right: [Biquad], preampDB: Float, level: Float, autoGainDB: Float,
                limitDB: Float, mono: Bool, bypass: Bool) {
        os_unfair_lock_lock(lock)
        for i in 0..<min(left.count, DSP.stages) { pendingL[i] = left[i] }
        for i in 0..<min(right.count, DSP.stages) { pendingR[i] = right[i] }
        pPreamp = pow(10, preampDB / 20); pLevel = level; pAutoGain = pow(10, autoGainDB / 20)
        pLimit = pow(10, limitDB / 20); pMono = mono; pBypass = bypass
        dirty = true
        os_unfair_lock_unlock(lock)
    }

    @inline(__always) private func softClip(_ x: Float) -> Float {
        let a = abs(x)
        if a <= 0.8 { return x }
        return (x < 0 ? -1 : 1) * (0.8 + 0.2 * tanh((a - 0.8) / 0.2))
    }

    @inline(__always) private func run(_ c: Biquad, _ x: Double, _ s: UnsafeMutablePointer<Double>) -> Double {
        let y = c.b0 * x + s[0]
        s[0] = c.b1 * x - c.a1 * y + s[1]
        s[1] = c.b2 * x - c.a2 * y
        return y
    }

    func process(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        // Toma parámetros nuevos sólo si el bloqueo está libre: el hilo de audio nunca espera.
        if os_unfair_lock_trylock(lock) {
            if dirty {
                coefsL.update(from: pendingL, count: DSP.stages)
                coefsR.update(from: pendingR, count: DSP.stages)
                preamp = pPreamp; level = pLevel; autoGain = pAutoGain; limit = pLimit
                mono = pMono; bypass = pBypass
                dirty = false
            }
            os_unfair_lock_unlock(lock)
        }

        let outs = UnsafeMutableAudioBufferListPointer(output)
        for b in outs where b.mData != nil { memset(b.mData, 0, Int(b.mDataByteSize)) }
        guard outs.count > 0, let o0 = outs[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let oc = Int(max(outs[0].mNumberChannels, 1))
        let frames = Int(outs[0].mDataByteSize) / (4 * oc)
        // Si el dispositivo es no intercalado y mono por buffer, el canal derecho va al segundo buffer.
        let o1: UnsafeMutablePointer<Float>? = (oc == 1 && outs.count > 1)
            ? outs[1].mData?.assumingMemoryBound(to: Float.self) : nil

        // El tap es el último stream de entrada con datos (los micrófonos del dispositivo van deshabilitados).
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var ip: UnsafeMutablePointer<Float>? = nil
        var ic = 1, inFrames = 0, seen = 0
        for b in ins where b.mData != nil && b.mDataByteSize > 0 {
            seen += 1
            ip = b.mData!.assumingMemoryBound(to: Float.self)
            ic = Int(max(b.mNumberChannels, 1))
            inFrames = Int(b.mDataByteSize) / (4 * ic)
        }
        inputStreamsSeen = seen
        callbacks &+= 1

        var sumL: Float = 0, sumR: Float = 0, pk: Float = 0
        var pkL = peakL, pkR = peakR, gr = grMin
        var cLR = 0.0, cLL = 0.0, cRR = 0.0
        for i in 0..<frames {
            var l: Float = 0, r: Float = 0
            if let ip, i < inFrames {
                l = ip[i * ic]
                r = ic > 1 ? ip[i * ic + 1] : l
            }
            pk = max(pk, abs(l), abs(r))

            agSmooth += (autoGain - agSmooth) * agCoef
            if !bypass {
                var dl = Double(l * preamp), dr = Double(r * preamp)
                for s in 0..<DSP.stages {
                    dl = run(coefsL[s], dl, state + s * 4)
                    dr = run(coefsR[s], dr, state + s * 4 + 2)
                }
                l = Float(dl) * agSmooth; r = Float(dr) * agSmooth
                if mono { let m = (l + r) * 0.5; l = m; r = m }
            }

            if fade < 1 { fade = min(1, fade + fadeStep) }
            let g = level * fade
            l *= g; r *= g

            // OVER: lo que habría saturado antes del limitador
            if abs(l) > 1 { overL = true }
            if abs(r) > 1 { overR = true }
            // Limitador de picos: ataque instantáneo, liberación de 150 ms
            let a = max(abs(l), abs(r))
            limGain = 1 - (1 - limGain) * limRelease
            if a * limGain > limit { limGain = limit / a }
            l *= limGain; r *= limGain
            gr = min(gr, limGain)

            l = softClip(l); r = softClip(r)

            sumL += l * l; sumR += r * r
            pkL = max(pkL, abs(l)); pkR = max(pkR, abs(r))
            let dl = Double(l), dr = Double(r)
            cLR += dl * dr; cLL += dl * dl; cRR += dr * dr

            let m = (dl + dr) * 0.5
            for b in 0..<DSP.bands {
                let y = run(anaCoefs[b], m, anaState + b * 2)
                anaSum[b] += Float(y * y)
            }

            let kl = run(kHP, run(kShelf, dl, kState), kState + 2)
            let kr = run(kHP, run(kShelf, dr, kState + 4), kState + 6)
            kSum += kl * kl + kr * kr
            kCount += 1
            if kCount >= kBlockLen {
                lufsBlocks[lufsBlockCount % DSP.lufsRing] = kSum / Double(kCount)
                lufsBlockCount += 1
                kSum = 0; kCount = 0
            }

            scopeSkip.toggle()
            if !scopeSkip {
                scopeX[scopeIndex] = (r - l) * 0.7071
                scopeY[scopeIndex] = (l + r) * 0.7071
                scopeIndex = (scopeIndex + 1) % DSP.scopeSize
            }

            if oc >= 2 { o0[i * oc] = l; o0[i * oc + 1] = r }
            else if let o1 { o0[i] = l; o1[i] = r }
            else { o0[i] = (l + r) * 0.5 }
        }
        if frames > 0 {
            rmsL = sqrt(sumL / Float(frames)); rmsR = sqrt(sumR / Float(frames))
            for b in 0..<DSP.bands {
                spectrum[b] = sqrt(anaSum[b] / Float(frames))
                anaSum[b] = 0
            }
        }
        inputPeak = pk
        peakL = pkL; peakR = pkR; grMin = gr
        corrLR += cLR; corrLL += cLL; corrRR += cRR
    }
}

// MARK: - Tap del sistema + dispositivo agregado privado

struct AudioError: LocalizedError {
    let step: String, code: OSStatus
    var errorDescription: String? { "\(step) (\(code))" }
}

private func check(_ status: OSStatus, _ step: String) throws {
    if status != noErr { throw AudioError(step: step, code: status) }
}

/// Captura la mezcla de todas las apps (excepto ésta y las excluidas), la silencia en origen y la
/// reproduce procesada en el dispositivo de salida real. Todo es privado del proceso: si la app se
/// cierra o falla, macOS destruye el tap y el audio vuelve a sonar normal.
final class TapEngine {
    let dsp = DSP()
    private(set) var sampleRate: Double = 48000
    private(set) var inputStreamCount = 0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var rateListener: AudioObjectPropertyListenerBlock?
    var onSampleRateChange: (() -> Void)?

    var isRunning: Bool { procID != nil }

    func start(output: AudioObjectID, exclude: [AudioObjectID]) throws {
        stop()
        do {
            guard let outUID = readString(output, kAudioDevicePropertyDeviceUID) else {
                throw AudioError(step: "Dispositivo de salida no válido", code: -1)
            }
            let me = ownProcessObject()
            guard me != kAudioObjectUnknown else {
                throw AudioError(step: "No se pudo excluir la propia app del tap", code: -1)
            }

            let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [me] + exclude.filter { $0 != me })
            tap.uuid = UUID()
            tap.name = "MAD Equalizer"
            tap.isPrivate = true
            tap.muteBehavior = .muted
            var t = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateProcessTap(tap, &t), "Crear tap del sistema")
            tapID = t

            let desc: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MAD Equalizer",
                kAudioAggregateDeviceUIDKey: "mad-eq-" + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                   kAudioSubTapUIDKey: tap.uuid.uuidString]],
            ]
            var agg = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg), "Crear dispositivo agregado")
            aggregateID = agg

            sampleRate = readValue(agg, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, Float64(48000))
            dsp.prepare(sampleRate: sampleRate)

            let dsp = self.dsp
            var pid: AudioDeviceIOProcID?
            try check(AudioDeviceCreateIOProcIDWithBlock(&pid, agg, nil) { _, inData, _, outData, _ in
                dsp.process(inData, outData)
            }, "Crear proceso de audio")
            procID = pid
            enableOnlyTapInput()

            var a = propAddress(kAudioDevicePropertyNominalSampleRate)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.onSampleRateChange?() }
            }
            AudioObjectAddPropertyListenerBlock(agg, &a, DispatchQueue.main, listener)
            rateListener = listener

            try check(AudioDeviceStart(agg, pid), "Iniciar audio")
        } catch {
            stop()
            throw error
        }
    }

    /// El agregado expone también el micrófono del dispositivo de salida (p. ej. audífonos
    /// Bluetooth). Usarlo los pasaría a modo llamada, así que sólo se deja activo el tap (el último stream).
    private func enableOnlyTapInput() {
        guard let procID else { return }
        let streams = readIDs(aggregateID, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        inputStreamCount = streams.count
        let n = streams.count
        guard n > 1 else { return }
        let bytes = 12 + 4 * n
        let raw = UnsafeMutableRawPointer.allocate(byteCount: max(bytes, 16), alignment: 8)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(n), toByteOffset: 8, as: UInt32.self)
        for i in 0..<n { raw.storeBytes(of: UInt32(i == n - 1 ? 1 : 0), toByteOffset: 12 + 4 * i, as: UInt32.self) }
        var a = propAddress(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        AudioObjectSetPropertyData(aggregateID, &a, 0, nil, UInt32(bytes), raw)
    }

    func stop() {
        if let rateListener, aggregateID != kAudioObjectUnknown {
            var a = propAddress(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(aggregateID, &a, DispatchQueue.main, rateListener)
        }
        rateListener = nil
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }
}
