import SwiftUI
import PublishKit

struct DispatchRootView: View {
    let controller: DispatchController

    var body: some View {
        ContentView(model: controller.state, controller: controller)
            .frame(minWidth: 1040, minHeight: 720)
    }
}
