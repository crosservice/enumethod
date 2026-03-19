'use client';

import { useCallback } from 'react';
import { useAuth } from '@/lib/auth-context';

export function useApi() {
  const { accessToken, refresh } = useAuth();

  const apiFetch = useCallback(
    async (path: string, options: RequestInit = {}): Promise<Response> => {
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        ...(options.headers as Record<string, string> || {}),
      };

      if (accessToken) {
        headers['Authorization'] = `Bearer ${accessToken}`;
      }

      let res = await fetch(`/api${path}`, { ...options, headers });

      if (res.status === 401) {
        const refreshed = await refresh();
        if (refreshed) {
          // Token was refreshed, retry
          res = await fetch(`/api${path}`, { ...options, headers });
        }
      }

      return res;
    },
    [accessToken, refresh],
  );

  return { apiFetch };
}
