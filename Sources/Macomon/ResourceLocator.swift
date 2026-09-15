import Foundation

enum ResourceLocator {
    static func root() -> URL {
        if let resources = Bundle.main.resourceURL {
            let embeddedBundleURL = resources.appendingPathComponent("Macomon_Macomon.bundle", isDirectory: true)
            if let embeddedBundle = Bundle(url: embeddedBundleURL),
               let embeddedResources = embeddedBundle.resourceURL {
                return embeddedResources
            }
        }

        return Bundle.module.resourceURL!
    }

    static func dogMarkURL() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("MacomonDogMark.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
