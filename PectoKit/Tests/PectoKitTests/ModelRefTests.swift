import Testing
@testable import PectoKit

struct ModelRefTests {
    @Test func bareModelStringIsAnthropic() {
        let ref = ModelRef.parse("claude-sonnet-5")
        #expect(ref == ModelRef(provider: .anthropic, model: "claude-sonnet-5"))
    }

    @Test func qualifiedFormsPickTheirProvider() {
        #expect(ModelRef.parse("anthropic/claude-opus-4-8") == ModelRef(provider: .anthropic, model: "claude-opus-4-8"))
        #expect(ModelRef.parse("openai/gpt-5.1") == ModelRef(provider: .openai, model: "gpt-5.1"))
        #expect(ModelRef.parse("gemini/gemini-2.5-flash") == ModelRef(provider: .gemini, model: "gemini-2.5-flash"))
        #expect(ModelRef.parse("xai/grok-4") == ModelRef(provider: .xai, model: "grok-4"))
        #expect(ModelRef.parse("apple/on-device") == ModelRef(provider: .apple, model: "on-device"))
    }

    @Test func unknownPrefixIsTreatedAsBareAnthropicModel() {
        let ref = ModelRef.parse("mystery/some-model")
        #expect(ref == ModelRef(provider: .anthropic, model: "mystery/some-model"))
    }

    @Test func emptyModelAfterKnownPrefixFallsBackToAnthropicVerbatim() {
        let ref = ModelRef.parse("openai/")
        #expect(ref == ModelRef(provider: .anthropic, model: "openai/"))
    }

    @Test func whitespaceIsTrimmed() {
        let ref = ModelRef.parse("  openai/gpt-5.1\n")
        #expect(ref == ModelRef(provider: .openai, model: "gpt-5.1"))
    }

    @Test func qualifiedRoundTrips() {
        let raw = "gemini/gemini-2.5-pro"
        #expect(ModelRef.parse(raw).qualified == raw)
    }
}

struct ProviderCatalogTests {
    @Test func everyProviderHasCatalogInfo() {
        for provider in ProviderID.allCases {
            let info = ProviderCatalog.info(for: provider)
            #expect(info.id == provider)
            #expect(!info.defaultModel.isEmpty)
            #expect(!info.selectableModels.isEmpty)
        }
    }

    @Test func onlyAppleNeedsNoKey() {
        for info in ProviderCatalog.all {
            #expect(info.requiresAPIKey == (info.id != .apple))
        }
    }

    @Test func defaultRefMatchesAnthropicCatalogDefault() {
        #expect(ProviderCatalog.defaultModelRef.provider == .anthropic)
        #expect(ProviderCatalog.defaultModelRef.model == ProviderCatalog.info(for: .anthropic).defaultModel)
    }
}
