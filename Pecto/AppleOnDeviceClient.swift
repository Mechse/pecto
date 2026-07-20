import Foundation
import PectoKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the on-device model can run here — drives picker visibility and
/// the Settings row for the Apple provider.
enum AppleModelAvailability: Equatable {
    case available
    case unavailable(String)
    case unsupportedOS

    static func check() -> AppleModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return .unavailable("Turn on Apple Intelligence in System Settings to use it.")
                case .deviceNotEligible:
                    return .unavailable("This Mac doesn't support Apple Intelligence.")
                case .modelNotReady:
                    return .unavailable("The model is still downloading — try again in a bit.")
                @unknown default:
                    return .unavailable("The on-device model isn't available right now.")
                }
            }
        }
        #endif
        return .unsupportedOS
    }

    var isAvailable: Bool { self == .available }

    /// Settings-row text when the model can't run.
    var explanation: String? {
        switch self {
        case .available: nil
        case .unavailable(let reason): reason
        case .unsupportedOS: "Requires macOS 26 with Apple Intelligence."
        }
    }
}

/// Runs prompts on Apple's on-device model. Lives in the app target (not
/// PectoKit) so the package needs no FoundationModels SDK to build.
struct AppleOnDeviceClient: ModelProviderClient {
    let id: ProviderID = .apple

    func run(prompt: RunPrompt, apiKey: String?, model: String) async throws -> RunOutput {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard AppleModelAvailability.check() == .available else {
                throw RunError(AppleModelAvailability.check().explanation ?? "The on-device model isn't available.")
            }
            do {
                let session = LanguageModelSession(instructions: prompt.system)
                let response = try await session.respond(to: prompt.user)
                // The framework reports no token counts.
                return RunOutput(text: response.content, usage: RunUsage(inputTokens: nil, outputTokens: nil))
            } catch let error as LanguageModelSession.GenerationError {
                throw RunError(Self.message(for: error))
            } catch {
                throw RunError("The on-device model couldn't finish this task.")
            }
        }
        #endif
        throw RunError("The Apple on-device model requires macOS 26 with Apple Intelligence.")
    }

    func validateKey(_ apiKey: String) async throws {
        // Key-less provider; nothing to validate.
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            "That text is too long for the on-device model. Try a shorter clipboard or a cloud model."
        case .guardrailViolation:
            "The on-device model declined this content. Your clipboard is unchanged."
        case .assetsUnavailable:
            "The on-device model isn't ready. Check Apple Intelligence in System Settings."
        default:
            "The on-device model couldn't finish this task."
        }
    }
    #endif
}
