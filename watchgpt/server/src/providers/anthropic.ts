// LLM leg direct to Anthropic (recommended default for production: no reseller
// fee, no OpenRouter ToS ambiguity, one fewer hop). OpenRouter stays available
// for model breadth via LLM_PROVIDER=openrouter.

import Anthropic from '@anthropic-ai/sdk';
import { config } from '../config.ts';
import type { ChatMessage, LLMProvider, LLMUsage } from './types.ts';
import { ProviderError } from './real.ts';

let client: Anthropic | undefined;

export const anthropicLLM: LLMProvider = {
  name: 'anthropic',
  async *stream(messages: ChatMessage[], { model, signal }) {
    client ??= new Anthropic({ apiKey: config.anthropicKey, maxRetries: 1 });
    const system = messages.filter((m) => m.role === 'system').map((m) => m.content).join('\n\n');
    const turns = messages
      .filter((m): m is ChatMessage & { role: 'user' | 'assistant' } => m.role !== 'system')
      .map((m) => ({ role: m.role, content: m.content }));

    try {
      const stream = client.messages.stream(
        {
          model,
          // Spoken replies are 1-3 sentences; the cap is a runaway guard, not a target.
          max_tokens: 1024,
          system,
          messages: turns,
          // Voice is latency-bound: skip thinking on Sonnet 5 (Haiku 4.5 doesn't think unless asked).
          ...(model.startsWith('claude-sonnet') ? { thinking: { type: 'disabled' as const } } : {}),
        },
        { signal },
      );
      for await (const event of stream) {
        if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') yield event.delta.text;
      }
      const final = await stream.finalMessage();
      const usage: LLMUsage = { input_tokens: final.usage.input_tokens, output_tokens: final.usage.output_tokens };
      return usage;
    } catch (err) {
      if (signal?.aborted) return undefined;
      if (err instanceof Anthropic.RateLimitError) throw new ProviderError('rate_limited', 'llm: rate limited', true);
      if (err instanceof Anthropic.APIError) {
        const status = err.status ?? 0;
        throw new ProviderError('provider_error', `llm ${status}: ${err.message}`, status >= 500 || status === 529);
      }
      throw err;
    }
  },
};
