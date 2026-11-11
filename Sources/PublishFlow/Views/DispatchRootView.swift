import SwiftUI
import PublishKit

struct DispatchRootView: View {
    let controller: DispatchController
    var updates: UpdateController? = nil
    var shortcuts: ShortcutController? = nil

    var body: some View {
        ContentView(model: controller.state, controller: controller, updates: updates, shortcuts: shortcuts)
            .fixedSize()
    }
}
