/// Picks the model a task runs with when neither the task nor the settings
/// name one. A stored API key is a deliberate setup signal, so it outranks
/// the built-in on-device model; with neither, the Mac simply can't run
/// tasks and the caller must say so.
public enum DefaultModelResolution {
    /// Nil when the Mac has no usable model at all.
    public static func resolve(
        storedKeyProviders: Set<ProviderID>,
        appleAvailable: Bool
    ) -> ModelRef? {
        // ProviderCatalog.all order IS the precedence order.
        for info in ProviderCatalog.all
        where info.requiresAPIKey && storedKeyProviders.contains(info.id) {
            return ModelRef(provider: info.id, model: info.defaultModel)
        }
        guard appleAvailable else { return nil }
        return ModelRef(provider: .apple, model: ProviderCatalog.info(for: .apple).defaultModel)
    }
}
