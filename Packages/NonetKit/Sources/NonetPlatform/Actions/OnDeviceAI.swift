// 担当: platform-actions
import Foundation
import NonetCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 端末内の言語モデル（FoundationModels、macOS 26 以降）で選択中のテキストを処理する
enum OnDeviceAI {
    /// モデルへの指示。画面には出ないので英語のまま（日本語の文には日本語で答える）
    static let instructions = """
        You process text for a Mac user. Follow the user's instruction and apply it to the text that follows \
        the line "---". Reply with the resulting text only, without any preamble, explanation, quotes or Markdown \
        code fences. Unless the instruction says otherwise, reply in the same language as the text.
        """

    static func prompt(instruction: String, text: String) -> String {
        "\(instruction.trimmingCharacters(in: .whitespacesAndNewlines))\n\n---\n\(text)"
    }

    /// 使えなければ理由を添えた NonetError.unavailable
    static func checkAvailability() throws {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return
            case .unavailable(.deviceNotEligible):
                throw NonetError.unavailable(String(localized: "この Mac は Apple Intelligence に対応していないため、AI アクションを使えません", bundle: .nonetActions))
            case .unavailable(.appleIntelligenceNotEnabled):
                throw NonetError.unavailable(String(localized: "Apple Intelligence がオフになっています。システム設定の「Apple Intelligence と Siri」でオンにしてください", bundle: .nonetActions))
            case .unavailable(.modelNotReady):
                throw NonetError.unavailable(String(localized: "Apple Intelligence の準備がまだ終わっていません。しばらくしてからもう一度お試しください", bundle: .nonetActions))
            case .unavailable:
                throw NonetError.unavailable(String(localized: "Apple Intelligence を今は使えません", bundle: .nonetActions))
            }
        }
        #endif
        throw NonetError.unavailable(String(localized: "AI アクションには macOS 26 以降が必要です", bundle: .nonetActions))
    }

    @MainActor
    static func respond(instruction: String, text: String) async throws -> String {
        try checkAvailability()
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: prompt(instruction: instruction, text: text))
                let result = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else {
                    throw NonetError.actionFailed(String(localized: "AI から結果が返りませんでした", bundle: .nonetActions))
                }
                return result
            } catch let error as NonetError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw mapped(error)
            }
        }
        #endif
        throw NonetError.unavailable(String(localized: "AI アクションには macOS 26 以降が必要です", bundle: .nonetActions))
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func mapped(_ error: Error) -> NonetError {
        ActionLog.logger.error("AI の処理に失敗しました: \(String(describing: error))")
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return .actionFailed(String(localized: "選択したテキストが長すぎます", bundle: .nonetActions))
            case .guardrailViolation, .refusal:
                return .actionFailed(String(localized: "このテキストは AI で処理できませんでした", bundle: .nonetActions))
            case .unsupportedLanguageOrLocale:
                return .actionFailed(String(localized: "このテキストの言語には対応していません", bundle: .nonetActions))
            default:
                break
            }
        }
        let headline = String(localized: "AI の処理に失敗しました", bundle: .nonetActions)
        return .actionFailed(ActionText.message(headline, detail: error.localizedDescription))
    }
    #endif
}
