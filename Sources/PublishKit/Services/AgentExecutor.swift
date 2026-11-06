import Foundation

public enum AgentExecutor {
    public static func run(llm: any LLMSession, bridge: EgoBridge, goal: String,
                           onEvent: @escaping @Sendable (String) -> Void,
                           onStage: (@Sendable (ChannelStage) async throws -> Void)? = nil) async throws -> EgoBridge.Finish {
        let loop = AgentLoop(llm: llm, bridge: bridge, maxSteps: 20)
        loop.onEvent = onEvent
        loop.onStage = onStage
        return try await loop.run(goal: goal)
    }
}
