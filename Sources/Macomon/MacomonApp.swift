import AppKit

@main
enum MacomonApp {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            if !SelfTest.run() {
                exit(EXIT_FAILURE)
            }
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
