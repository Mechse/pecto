import { MockLanguageModelV3 } from "ai/test";

/**
 * A deterministic model for tests and key-less local runs: replies with the
 * scripted texts in order (the last one repeats). With no script it echoes a
 * short acknowledgement of the prompt.
 */
export function createScriptedModel(script: string[] = []) {
  let turn = 0;
  return new MockLanguageModelV3({
    modelId: "offline",
    doGenerate: async (options) => {
      const scripted = script[Math.min(turn, script.length - 1)];
      turn += 1;
      const lastMessage = options.prompt.at(-1);
      const promptPreview =
        lastMessage && Array.isArray(lastMessage.content)
          ? lastMessage.content
              .map((part) => (part.type === "text" ? part.text : ""))
              .join(" ")
              .slice(0, 80)
          : "";
      const text = scripted ?? `(offline model) Acknowledged: ${promptPreview}…`;
      return {
        content: [{ type: "text" as const, text }],
        finishReason: { unified: "stop" as const, raw: undefined },
        usage: {
          inputTokens: { total: 1, noCache: 1, cacheRead: undefined, cacheWrite: undefined },
          outputTokens: { total: 1, text: 1, reasoning: undefined },
        },
        warnings: [],
      };
    },
  });
}
