//
//  UsageProviderRegistry.swift
//  Light Stats
//

import Foundation

/// Compile-time list of usage providers. Order matches `AIProvider.allCases`.
enum UsageProviderRegistry {

    static let all: [UsageProviderDescriptor] = [
        descriptor(
            id: .claude,
            credential: .localDiscovered,
            iconAssetName: "claudeLogo",
            symbolFallback: "sparkles",
            cliName: "claude",
            supportsWarmup: true,
            fetch: { try await ClaudeUsageService.fetch() },
            reset: { ClaudeUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .codex,
            credential: .localDiscovered,
            iconAssetName: "codexLogo",
            symbolFallback: "circle.hexagonpath",
            cliName: "codex",
            supportsWarmup: true,
            fetch: { try await CodexUsageService.fetch() },
            reset: { CodexUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .gemini,
            credential: .localDiscovered,
            iconAssetName: "geminiLogo",
            symbolFallback: "sparkle",
            cliName: "gemini",
            supportsWarmup: false,
            fetch: { try await GeminiUsageService.fetch() },
            reset: { GeminiUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .deepseek,
            credential: .apiToken,
            iconAssetName: "deepseekLogo",
            symbolFallback: "yensign.circle",
            cliName: nil,
            supportsWarmup: false,
            showsBalance: true,
            fetch: { try await DeepSeekUsageService.fetch() },
            reset: { DeepSeekUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .grok,
            credential: .localDiscovered,
            iconAssetName: "grokLogo",
            symbolFallback: "bolt",
            cliName: "grok",
            supportsWarmup: false,
            fetch: { try await GrokUsageService.fetch() },
            reset: { GrokUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .zai,
            credential: .apiToken,
            iconAssetName: "zaiLogo",
            symbolFallback: "cube",
            cliName: nil,
            supportsWarmup: false,
            showsBalance: true,
            fetch: { try await ZAIUsageService.fetch() },
            reset: { ZAIUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .minimax,
            credential: .apiToken,
            iconAssetName: "minimaxLogo",
            symbolFallback: "square.grid.2x2",
            cliName: nil,
            supportsWarmup: false,
            showsBalance: true,
            fetch: { try await MiniMaxUsageService.fetch() },
            reset: { MiniMaxUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .openrouter,
            credential: .apiToken,
            iconAssetName: "openrouterLogo",
            symbolFallback: "arrow.triangle.branch",
            cliName: nil,
            supportsWarmup: false,
            showsBalance: true,
            fetch: { try await OpenRouterUsageService.fetch() },
            reset: { OpenRouterUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .warp,
            credential: .apiToken,
            iconAssetName: "warpLogo",
            symbolFallback: "terminal",
            cliName: nil,
            supportsWarmup: false,
            fetch: { try await WarpUsageService.fetch() },
            reset: { WarpUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .trae,
            credential: .apiToken,
            iconAssetName: "traeLogo",
            symbolFallback: "paintbrush.pointed",
            cliName: nil,
            supportsWarmup: false,
            fetch: { try await TraeUsageService.fetch() },
            reset: { TraeUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .opencodego,
            credential: .apiToken,
            iconAssetName: "opencodegoLogo",
            symbolFallback: "chevron.left.forwardslash.chevron.right",
            cliName: nil,
            supportsWarmup: false,
            fetch: { try await OpenCodeGoUsageService.fetch() },
            reset: { OpenCodeGoUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .cursor,
            credential: .ideDatabase,
            iconAssetName: "cursorLogo",
            symbolFallback: "rectangle.and.pencil.and.ellipsis",
            cliName: "Cursor",
            supportsWarmup: false,
            fetch: { try await CursorUsageService.fetch() },
            reset: { CursorUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .kimi,
            credential: .apiToken,
            iconAssetName: "kimiLogo",
            symbolFallback: "moon.stars",
            cliName: nil,
            supportsWarmup: false,
            fetch: { try await KimiUsageService.fetch() },
            reset: { KimiUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .qoder,
            credential: .apiToken,
            iconAssetName: "qoderLogo",
            symbolFallback: "magnifyingglass.circle",
            cliName: nil,
            supportsWarmup: false,
            tokenHintKey: "aiUsage.qoder.tokenHint",
            fetch: { try await QoderUsageService.fetch() },
            reset: { QoderUsageService.resetCredentialCache() }
        ),
        descriptor(
            id: .mimo,
            credential: .apiToken,
            iconAssetName: "mimoLogo",
            symbolFallback: "cpu",
            cliName: nil,
            supportsWarmup: false,
            showsBalance: true,
            tokenHintKey: "aiUsage.mimo.tokenHint",
            fetch: { try await MiMoUsageService.fetch() },
            reset: { MiMoUsageService.resetCredentialCache() }
        )
    ]

    static func descriptor(for id: AIProvider) -> UsageProviderDescriptor? {
        all.first { $0.id == id }
    }

    static func fetch(_ id: AIProvider) async throws -> ProviderUsageSnapshot {
        // A missing descriptor is a configuration gap, not a programmer error:
        // the caller is a user toggle, so surface it as a fetch failure.
        guard let desc = descriptor(for: id) else {
            throw AIUsageError.endpointNotFound
        }
        return try await desc.fetch()
    }

    static func resetCredentialCache(_ id: AIProvider) {
        descriptor(for: id)?.resetCredentialCache()
    }

    private static func descriptor(
        id: AIProvider,
        credential: CredentialSource,
        iconAssetName: String,
        symbolFallback: String,
        cliName: String?,
        supportsWarmup: Bool,
        showsBalance: Bool = false,
        tokenHintKey: String? = nil,
        fetch: @escaping @Sendable () async throws -> ProviderUsageSnapshot,
        reset: @escaping @Sendable () -> Void
    ) -> UsageProviderDescriptor {
        UsageProviderDescriptor(
            id: id,
            credential: credential,
            displayNameKey: "aiUsage.\(id.rawValue)",
            iconAssetName: iconAssetName,
            symbolFallback: symbolFallback,
            cliName: cliName,
            supportsWarmup: supportsWarmup,
            showsBalance: showsBalance,
            tokenHintKey: tokenHintKey,
            fetch: fetch,
            resetCredentialCache: reset
        )
    }
}
