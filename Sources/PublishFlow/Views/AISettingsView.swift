import SwiftUI
import PublishKit

struct AISettingsView: View {
    @State private var controller = AISettingsController()

    var body: some View {
        @Bindable var controller = controller
        VStack(alignment: .leading, spacing: 16) {
            TextField("接口地址", text: $controller.configuration.endpoint)
                .accessibilityLabel("AI 接口基础地址")
            SecureField("API Key", text: $controller.key)
            HStack {
                TextField("模型", text: $controller.configuration.model)
                if !controller.models.isEmpty {
                    Menu("选择模型") {
                        ForEach(controller.models, id: \.self) { model in
                            Button(model) { controller.configuration.model = model }
                        }
                    }
                }
            }
            HStack {
                Button("获取模型", action: controller.fetchModels)
                Button("测试连接", action: controller.testConnection)
                    .disabled(controller.configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if controller.isConnecting { Button("取消") { controller.invalidate() } }
                Spacer()
                Button("保存", action: controller.save)
            }
            if let message = controller.message { Text(message).font(.caption).textSelection(.enabled) }
        }
        .textFieldStyle(.roundedBorder)
        .disabled(!controller.loaded)
        .onAppear { controller.load() }
        .onChange(of: controller.configuration) { old, new in
            controller.invalidate()
            if old.endpoint != new.endpoint { controller.models = [] }
        }
        .onChange(of: controller.key) { controller.invalidate(); controller.models = [] }
        .onDisappear { controller.invalidate() }
    }
}
