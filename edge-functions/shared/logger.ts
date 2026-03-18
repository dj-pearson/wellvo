/**
 * Structured JSON logger for edge functions.
 * Outputs one JSON object per line, compatible with Docker json-file log driver.
 */

type LogLevel = "info" | "warn" | "error";

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  path?: string;
  userId?: string;
  statusCode?: number;
  durationMs?: number;
  message: string;
  error?: string;
  stack?: string;
}

function emit(entry: LogEntry): void {
  const line = JSON.stringify(entry);
  if (entry.level === "error") {
    console.error(line);
  } else if (entry.level === "warn") {
    console.warn(line);
  } else {
    console.log(line);
  }
}

export function logInfo(message: string, fields?: Partial<LogEntry>): void {
  emit({
    timestamp: new Date().toISOString(),
    level: "info",
    message,
    ...fields,
  });
}

export function logWarn(message: string, fields?: Partial<LogEntry>): void {
  emit({
    timestamp: new Date().toISOString(),
    level: "warn",
    message,
    ...fields,
  });
}

export function logError(message: string, error?: unknown, fields?: Partial<LogEntry>): void {
  const entry: LogEntry = {
    timestamp: new Date().toISOString(),
    level: "error",
    message,
    ...fields,
  };
  if (error instanceof Error) {
    entry.error = error.message;
    entry.stack = error.stack;
  } else if (error !== undefined) {
    entry.error = String(error);
  }
  emit(entry);
}

/**
 * Wrap a handler to log request start, completion, and errors with timing.
 */
export function withRequestLogging(
  path: string,
  userId: string | undefined,
  fn: () => Promise<Response>,
): Promise<Response> {
  const start = Date.now();
  logInfo("request_start", { path, userId });

  return fn()
    .then((response) => {
      logInfo("request_complete", {
        path,
        userId,
        statusCode: response.status,
        durationMs: Date.now() - start,
      });
      return response;
    })
    .catch((error) => {
      logError("request_error", error, {
        path,
        userId,
        durationMs: Date.now() - start,
      });
      throw error;
    });
}
