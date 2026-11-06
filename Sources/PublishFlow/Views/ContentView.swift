import SwiftUI
import PublishKit

struct ContentView: View {
    @Bindable var model: DispatchModel
    let controller: DispatchController
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            CompactView(model: model, controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 20) {
                Text("工作台").font(.title2).fontWeight(.medium)
                Text("内容与简约界面实时同步。发布前，请到浏览器检查每一个渠道。")
                    .font(.callout).foregroundStyle(.secondary)
                GroupBox("模型配置 · DeepSeek") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("API Key", text: $model.apiKey)
                        TextField("模型", text: $model.model)
                        Text("https://api.deepseek.com").font(.caption).foregroundStyle(.secondary)
                    }.textFieldStyle(.roundedBorder).padding(8)
                }.disabled(model.overallPhase != .pending)
                GroupBox("话题") {
                    TextField("多个话题以空格分隔", text: $model.tagsText).textFieldStyle(.roundedBorder).padding(8)
                }.disabled(model.overallPhase != .pending)
                GroupBox("运行记录") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if model.eventLog.isEmpty { Text("开始填写后，这里会记录各渠道的执行过程。").foregroundStyle(.secondary) }
                            ForEach(Array(model.eventLog.enumerated()), id: \.offset) { _, line in Text(line).textSelection(.enabled) }
                        }.font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.frame(minHeight: 200, maxHeight: .infinity)
                }
                Text("当前仅开放已接入的渠道。原型中的其他平台仍待适配与验证。")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }.padding(26).background(Color(red: 0.95, green: 0.95, blue: 0.925))
    }
}
