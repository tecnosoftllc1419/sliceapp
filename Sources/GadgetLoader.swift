import Foundation

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