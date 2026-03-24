import { env } from "./env";

interface ApiOptions {
  accessToken: string;
  body?: Record<string, unknown>;
}

interface ApiResponse<T = unknown> {
  status: number;
  ok: boolean;
  data: T;
}

export async function callEdgeFunction<T = unknown>(
  path: string,
  opts: ApiOptions
): Promise<ApiResponse<T>> {
  const url = `${env.edgeFunctionsUrl}${path}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${opts.accessToken}`,
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });

  const data = (await res.json()) as T;

  return {
    status: res.status,
    ok: res.status >= 200 && res.status < 300,
    data,
  };
}

export async function healthCheck(): Promise<boolean> {
  const url = `${env.edgeFunctionsUrl}/health`;
  try {
    console.log(`[healthCheck] Fetching: ${url}`);
    const res = await fetch(url);
    const text = await res.text();
    console.log(`[healthCheck] Status: ${res.status}, Body: ${text.substring(0, 200)}`);
    const data = JSON.parse(text) as { status: string };
    return data.status === "ok";
  } catch (err) {
    console.error(`[healthCheck] Failed for ${url}:`, err);
    return false;
  }
}
