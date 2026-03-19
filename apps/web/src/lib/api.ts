let getAccessToken: (() => string | null) | null = null;
let refreshFn: (() => Promise<boolean>) | null = null;

export function setAuthHelpers(
  tokenGetter: () => string | null,
  refresher: () => Promise<boolean>,
) {
  getAccessToken = tokenGetter;
  refreshFn = refresher;
}

export async function api(path: string, options: RequestInit = {}): Promise<Response> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };

  const token = getAccessToken?.();
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  let res = await fetch(`/api${path}`, { ...options, headers });

  if (res.status === 401 && refreshFn) {
    const refreshed = await refreshFn();
    if (refreshed) {
      const newToken = getAccessToken?.();
      if (newToken) {
        headers['Authorization'] = `Bearer ${newToken}`;
      }
      res = await fetch(`/api${path}`, { ...options, headers });
    }
  }

  return res;
}
