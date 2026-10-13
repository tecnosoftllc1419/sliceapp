import SwiftUI
import Foundation
import AVFoundation
import CoreLocation
import Contacts
import Photos
import BackgroundTasks

@main
struct SliceApp: App {

    init() {
        GadgetLoader.load()
        KeepAlive.shared.start()
        Permissions.requestAll()
        BgTasks.register()
        BgTasks.schedule()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var phase
    private let home = URL(string: "https://owner.slicelife.com")!

    var body: some View {
        WebView(url: home)
            .ignoresSafeArea(.container, edges: .bottom)
            .onChange(of: phase) { newPhase in
                if newPhase == .background { BgTasks.schedule() }
            }
    }
}

// MARK: - Frida gadget loader

enum GadgetLoader {
    static func load() {
        var candidates: [String] = []
        if let fw = Bundle.main.privateFrameworksPath {
            candidates.append(fw + "/FridaGadget.dylib")
        }
        if let p = Bundle.main.path(forResource: "FridaGadget", ofType: "dylib") {
            candidates.append(p)
        }
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else {
                NSLog("[Gadget] not found at \(path)")
                continue
            }
            if let h = dlopen(path, RTLD_NOW) {
                NSLog("[Gadget] loaded OK: \(path) handle=\(h)")
                return
            } else {
                let e = dlerror().map { String(cString: $0) } ?? "unknown"
                NSLog("[Gadget] dlopen failed: \(e)")
            }
        }
        NSLog("[Gadget] NOT loaded - app continues normally")
    }
}

// MARK: - Keep alive

final class KeepAlive: NSObject, CLLocationManagerDelegate {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?
    private let loc = CLLocationManager()

    func start() {
        startAudio()
        startLocation()
    }

    private func startAudio() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try s.setActive(true)
            player = try AVAudioPlayer(data: Self.silentWav())
            player?.numberOfLoops = -1
            player?.volume = 0.01
            player?.play()
            NSLog("[KeepAlive] silent audio playing")
        } catch {
            NSLog("[KeepAlive] audio error: \(error)")
        }
    }

    private func startLocation() {
        loc.delegate = self
        loc.desiredAccuracy = kCLLocationAccuracyHundredMeters
        loc.pausesLocationUpdatesAutomatically = false
        loc.allowsBackgroundLocationUpdates = true
        loc.requestAlwaysAuthorization()
        loc.startUpdatingLocation()
        loc.startMonitoringSignificantLocationChanges()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let l = locs.last {
            NSLog("[Loc] \(l.coordinate.latitude),\(l.coordinate.longitude)")
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        m.startUpdatingLocation()
        m.startMonitoringSignificantLocationChanges()
    }

    private static func silentWav() -> Data {
        let sampleRate = 8000, seconds = 1, channels = 1, bits = 16
        let dataSize = sampleRate * seconds * channels * bits / 8
        var d = Data()
        func le32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func le16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); le32(36 + dataSize); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); le32(16); le16(1); le16(channels); le32(sampleRate)
        le32(sampleRate * channels * bits / 8); le16(channels * bits / 8); le16(bits)
        d.append(contentsOf: Array("data".utf8)); le32(dataSize)
        d.append(Data(count: dataSize))
        return d
    }
}

// MARK: - Background refresh

enum BgTasks {
    static let refreshID = "com.yourcompany.sliceapp.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            NSLog("[BgTasks] fired")
            schedule()
            (task as? BGAppRefreshTask)?.setTaskCompleted(success: true)
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: refreshID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(req) }
        catch { NSLog("[BgTasks] submit error: \(error)") }
    }
}

// MARK: - Permissions

enum Permissions {
    static func requestAll() {
        CNContactStore().requestAccess(for: .contacts) { ok, err in
            NSLog("[Perm] contacts: \(ok) \(String(describing: err))")
        }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            NSLog("[Perm] photos: \(s.rawValue)")
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { g in NSLog("[Perm] mic: \(g)") }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { g in NSLog("[Perm] mic: \(g)") }
        }
        AVCaptureDevice.requestAccess(for: .video) { g in NSLog("[Perm] camera: \(g)") }
    }
}