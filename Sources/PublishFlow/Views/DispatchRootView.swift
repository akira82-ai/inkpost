import SwiftUI
import PublishKit

struct DispatchRootView: View {
    let controller: DispatchController
    var updates: UpdateController? = nil

    var body: some View {
        ContentView(model: controller.state, controller: controller, updates: updates)
            .fixedSize()
    }
}
