/**
 * Unified AI client for Anthropic (preferred) and OpenAI (fallback).
 * Config comes from Coolify Team Shared Variables:
 *   AI_DEFAULT_PROVIDER      anthropic | openai
 *   ANTHROPIC_API_KEY | CLAUDE_API_KEY
 *   OPENAI_GLOBAL_API
 *   DEFAULT_AI_MODEL         main model id
 *   LIGHTWEIGHT_AI_MODEL     small-task model id
 *   AI_TEMPERATURE           default temperature (float)
 *   AI_MAX_RETRIES           integer, default 2
 *   AI_TIMEOUT_MS            integer, default 60000
 *   AI_ENABLE_CACHING        "true" to enable Anthropic prompt caching
 */

type Provider = "anthropic" | "openai";

export type AiModelSize = "default" | "lightweight";

export interface AiMessage {
  role: "user" | "assistant";
  content: string;
}

export interface AiTool {
  name: string;
  description: string;
  /** JSON schema for the tool's input. */
  input_schema: Record<string, unknown>;
}

export interface AiGenerateOptions {
  system?: string;
  messages: AiMessage[];
  maxTokens?: number;
  temperature?: number;
  modelSize?: AiModelSize;  // default => DEFAULT_AI_MODEL, lightweight => LIGHTWEIGHT_AI_MODEL
  /** Cache the system prompt (Anthropic only). Useful for pSEO batches. */
  cacheSystem?: boolean;
  /** JSON response mode — tells the model to return parseable JSON. */
  json?: boolean;
  /**
   * Assistant prefill string. Anthropic only — injected as an assistant
   * message so the model continues from there. The returned text will have
   * this prefix re-prepended so callers see the complete response.
   * Useful to force JSON-only output: set prefill to "{" and the model
   * cannot emit preamble, code fences, or prose before the object.
   */
  prefill?: string;
  /**
   * Per-call timeout override in ms. Defaults to AI_TIMEOUT_MS env var (60s).
   * Long generations (full blog articles) should set this explicitly to
   * avoid depending on env configuration.
   */
  timeoutMs?: number;
  /**
   * Per-call retry override. Defaults to AI_MAX_RETRIES env var (2). Set to
   * 0 for long-running generations to avoid stacking multiple long timeouts
   * on top of each other.
   */
  maxRetries?: number;
  /**
   * Tools the model can call. Anthropic only in this implementation.
   * When combined with toolChoice, forces the model to return structured
   * output (eliminates JSON-parse failures on long HTML payloads).
   */
  tools?: AiTool[];
  /**
   * Force a specific tool call. Anthropic only.
   *   { type: "tool", name: "publish_blog_post" } — must call that tool
   *   { type: "any" }                              — must call some tool
   *   { type: "auto" }                             — may call a tool (default)
   */
  toolChoice?: { type: "tool"; name: string } | { type: "any" } | { type: "auto" };
}

export interface AiGenerateResult {
  text: string;
  provider: Provider;
  model: string;
  inputTokens?: number;
  outputTokens?: number;
  cacheCreationTokens?: number;
  cacheReadTokens?: number;
}

export class AiError extends Error {
  constructor(message: string, public status?: number) {
    super(message);
    this.name = "AiError";
  }
}

function env(name: string): string | undefined {
  const v = Deno.env.get(name);
  return v && v.trim() !== "" ? v : undefined;
}

function resolveProvider(): Provider {
  const pref = (env("AI_DEFAULT_PROVIDER") || "anthropic").toLowerCase();
  const hasAnthropic = !!(env("ANTHROPIC_API_KEY") || env("CLAUDE_API_KEY"));
  const hasOpenAI = !!env("OPENAI_GLOBAL_API");

  if (pref === "openai" && hasOpenAI) return "openai";
  if (pref === "anthropic" && hasAnthropic) return "anthropic";
  if (hasAnthropic) return "anthropic";
  if (hasOpenAI) return "openai";
  throw new AiError("No AI provider is configured (set ANTHROPIC_API_KEY or OPENAI_GLOBAL_API)");
}

function resolveModel(size: AiModelSize, provider: Provider): string {
  if (size === "lightweight") {
    const lw = env("LIGHTWEIGHT_AI_MODEL");
    if (lw) return lw;
  }
  const defaultModel = env("DEFAULT_AI_MODEL");
  if (defaultModel) return defaultModel;
  // Sensible fallbacks
  return provider === "anthropic" ? "claude-sonnet-4-6" : "gpt-4o-mini";
}

function resolveTemperature(opt?: number): number {
  if (typeof opt === "number") return opt;
  const raw = env("AI_TEMPERATURE");
  if (raw) {
    const n = parseFloat(raw);
    if (!Number.isNaN(n)) return n;
  }
  return 0.7;
}

function resolveMaxRetries(): number {
  const raw = env("AI_MAX_RETRIES");
  if (raw) {
    const n = parseInt(raw, 10);
    if (!Number.isNaN(n) && n >= 0) return n;
  }
  return 2;
}

function resolveTimeoutMs(): number {
  const raw = env("AI_TIMEOUT_MS");
  if (raw) {
    const n = parseInt(raw, 10);
    if (!Number.isNaN(n) && n > 0) return n;
  }
  return 60_000;
}

function cachingEnabled(): boolean {
  return (env("AI_ENABLE_CACHING") || "false").toLowerCase() === "true";
}

async function fetchWithRetry(
  url: string,
  init: RequestInit,
  maxRetries: number,
  timeoutMs: number,
): Promise<Response> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(url, { ...init, signal: ctrl.signal });
      clearTimeout(timer);
      if (res.status === 429 || res.status >= 500) {
        if (attempt < maxRetries) {
          const backoff = Math.min(2000 * (attempt + 1), 8000);
          await new Promise((r) => setTimeout(r, backoff));
          continue;
        }
      }
      return res;
    } catch (err) {
      clearTimeout(timer);
      lastErr = err;
      if (attempt < maxRetries) {
        const backoff = Math.min(2000 * (attempt + 1), 8000);
        await new Promise((r) => setTimeout(r, backoff));
        continue;
      }
    }
  }
  throw new AiError(`AI request failed: ${lastErr instanceof Error ? lastErr.message : String(lastErr)}`);
}

async function callAnthropic(opts: AiGenerateOptions): Promise<AiGenerateResult> {
  const apiKey = env("ANTHROPIC_API_KEY") || env("CLAUDE_API_KEY")!;
  const model = resolveModel(opts.modelSize ?? "default", "anthropic");
  const shouldCache = opts.cacheSystem !== false && cachingEnabled() && !!opts.system;

  const systemBlocks = opts.system
    ? [
        shouldCache
          ? { type: "text", text: opts.system, cache_control: { type: "ephemeral" } }
          : { type: "text", text: opts.system },
      ]
    : undefined;

  const messages = opts.messages.map((m) => ({ role: m.role, content: m.content }));
  if (opts.prefill) {
    messages.push({ role: "assistant", content: opts.prefill });
  }
  const body: Record<string, unknown> = {
    model,
    max_tokens: opts.maxTokens ?? 4096,
    temperature: resolveTemperature(opts.temperature),
    messages,
  };
  if (systemBlocks) body.system = systemBlocks;
  if (opts.tools && opts.tools.length > 0) {
    body.tools = opts.tools;
  }
  if (opts.toolChoice) {
    body.tool_choice = opts.toolChoice;
  }

  const res = await fetchWithRetry(
    "https://api.anthropic.com/v1/messages",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(body),
    },
    opts.maxRetries ?? resolveMaxRetries(),
    opts.timeoutMs ?? resolveTimeoutMs(),
  );

  if (!res.ok) {
    const text = await res.text();
    throw new AiError(`Anthropic ${res.status}: ${text.slice(0, 500)}`, res.status);
  }

  const data = await res.json();

  // Prefer tool_use output when tools were specified — Anthropic returns the
  // arguments as an already-parsed object, so serializing it with JSON.stringify
  // yields valid JSON with no risk of escape errors from long HTML bodies.
  let textContent = "";
  if (Array.isArray(data.content)) {
    const toolUse = data.content.find(
      (c: { type: string; input?: unknown }) => c.type === "tool_use" && c.input !== undefined,
    );
    if (toolUse && opts.tools && opts.tools.length > 0) {
      textContent = JSON.stringify(toolUse.input);
    } else {
      textContent = data.content
        .filter((c: { type: string }) => c.type === "text")
        .map((c: { text: string }) => c.text)
        .join("");
    }
  }
  if (opts.prefill && !opts.tools) {
    textContent = opts.prefill + textContent;
  }

  return {
    text: textContent,
    provider: "anthropic",
    model,
    inputTokens: data.usage?.input_tokens,
    outputTokens: data.usage?.output_tokens,
    cacheCreationTokens: data.usage?.cache_creation_input_tokens,
    cacheReadTokens: data.usage?.cache_read_input_tokens,
  };
}

async function callOpenAI(opts: AiGenerateOptions): Promise<AiGenerateResult> {
  const apiKey = env("OPENAI_GLOBAL_API")!;
  const model = resolveModel(opts.modelSize ?? "default", "openai");

  const messages: Array<{ role: string; content: string }> = [];
  if (opts.system) messages.push({ role: "system", content: opts.system });
  for (const m of opts.messages) messages.push({ role: m.role, content: m.content });

  const body: Record<string, unknown> = {
    model,
    messages,
    max_tokens: opts.maxTokens ?? 4096,
    temperature: resolveTemperature(opts.temperature),
  };
  if (opts.json) body.response_format = { type: "json_object" };

  const res = await fetchWithRetry(
    "https://api.openai.com/v1/chat/completions",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
    },
    opts.maxRetries ?? resolveMaxRetries(),
    opts.timeoutMs ?? resolveTimeoutMs(),
  );

  if (!res.ok) {
    const text = await res.text();
    throw new AiError(`OpenAI ${res.status}: ${text.slice(0, 500)}`, res.status);
  }

  const data = await res.json();
  const textContent = data.choices?.[0]?.message?.content ?? "";

  return {
    text: textContent,
    provider: "openai",
    model,
    inputTokens: data.usage?.prompt_tokens,
    outputTokens: data.usage?.completion_tokens,
  };
}

export async function aiGenerate(opts: AiGenerateOptions): Promise<AiGenerateResult> {
  const provider = resolveProvider();
  return provider === "anthropic" ? callAnthropic(opts) : callOpenAI(opts);
}

/** Substitute {{variable}} placeholders in a template string. */
export function renderTemplate(template: string, vars: Record<string, string>): string {
  return template.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, name) => vars[name] ?? "");
}

/**
 * Extract the first ```json ... ``` block (if any) or parse the full text as
 * JSON. If strict parsing fails, run a repair pass for the common mistakes
 * large language models make when emitting JSON that contains long string
 * values (HTML bodies in particular):
 *   1. Trailing commas before `}` or `]`.
 *   2. Raw newlines/tabs/carriage-returns embedded inside string values
 *      (must be escaped as \n \t \r in JSON).
 *   3. Invalid `\X` escape sequences where X is not one of " \ / b f n r t u
 *      (e.g. `\<`, `\'`, `\s`) — replaced with just X.
 * If repair still fails, the original SyntaxError is re-thrown so callers
 * can inspect the position.
 */
export function extractJson<T = unknown>(text: string): T {
  const fence = text.match(/```json\s*([\s\S]*?)```/i) ?? text.match(/```\s*([\s\S]*?)```/);
  const candidate = (fence ? fence[1] : text).trim();

  try {
    return JSON.parse(candidate) as T;
  } catch (err) {
    try {
      const repaired = repairLlmJson(candidate);
      return JSON.parse(repaired) as T;
    } catch {
      throw err; // surface the original error — more informative
    }
  }
}

/** Repair the common JSON emission mistakes from LLMs. Preserves meaning. */
function repairLlmJson(input: string): string {
  // Walk the string while tracking string-literal context so we only escape
  // raw control characters that appear INSIDE string values.
  let out = "";
  let inString = false;
  let escaped = false;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];

    if (escaped) {
      // Previous char was `\` — keep the escape sequence unless it's invalid.
      const validJsonEscape = /[\"\\/bfnrtu]/.test(ch);
      if (validJsonEscape) {
        out += ch;
      } else {
        // Drop the backslash; emit the literal character.
        out = out.slice(0, -1) + ch;
      }
      escaped = false;
      continue;
    }

    if (ch === "\\") {
      out += ch;
      escaped = true;
      continue;
    }

    if (ch === '"') {
      inString = !inString;
      out += ch;
      continue;
    }

    if (inString) {
      // Re-escape raw control chars that are illegal in JSON string literals.
      if (ch === "\n") { out += "\\n"; continue; }
      if (ch === "\r") { out += "\\r"; continue; }
      if (ch === "\t") { out += "\\t"; continue; }
    }

    out += ch;
  }

  // Strip trailing commas before `}` or `]`.
  out = out.replace(/,(\s*[}\]])/g, "$1");
  return out;
}
