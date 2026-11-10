import Foundation

@main
@MainActor
enum ApplicationStartup {
    private(set) static var instance: ApplicationInstance?

    static func main() {
        let stopping = CommandLine.arguments.contains("--stop-running-instance")
        do {
            let instance = try ApplicationInstance()
            switch try instance.start(request: stopping ? .stop : .activate) {
            case .primary:
                Self.instance = instance // Keep the kernel lease alive until process exit.
                PublishFlowApp.main()
            case .activatedExisting, .stopped:
                return
            }
        } catch {
            FileHandle.standardError.write(Data("Inkpost: \(error.localizedDescription)\n".utf8))
            if !stopping {
                LaunchFailurePresentation.show(error.localizedDescription)
            }
            exit(EXIT_FAILURE)
        }
    }
}
