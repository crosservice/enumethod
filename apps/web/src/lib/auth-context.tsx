'use client';

import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from 'react';
import { api } from './api';

interface JwtPayload {
  sub: number;
  username: string;
  role: string;
  mustReset: boolean;
  exp: number;
}

interface AuthState {
  user: JwtPayload | null;
  accessToken: string | null;
}

interface AuthContextType {
  user: JwtPayload | null;
  accessToken: string | null;
  isLoading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  refresh: () => Promise<boolean>;
}

const AuthContext = createContext<AuthContextType | null>(null);

function parseJwt(token: string): JwtPayload | null {
  try {
    const base64 = token.split('.')[1];
    const json = atob(base64.replace(/-/g, '+').replace(/_/g, '/'));
    return JSON.parse(json);
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [auth, setAuth] = useState<AuthState>({ user: null, accessToken: null });
  const [isLoading, setIsLoading] = useState(true);

  const refresh = useCallback(async (): Promise<boolean> => {
    const refreshToken = localStorage.getItem('refreshToken');
    if (!refreshToken) return false;

    try {
      const res = await fetch('/api/auth/refresh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refreshToken }),
      });
      if (!res.ok) throw new Error('Refresh failed');

      const data = await res.json();
      localStorage.setItem('refreshToken', data.refreshToken);
      const user = parseJwt(data.accessToken);
      setAuth({ user, accessToken: data.accessToken });
      return true;
    } catch {
      localStorage.removeItem('refreshToken');
      setAuth({ user: null, accessToken: null });
      return false;
    }
  }, []);

  useEffect(() => {
    refresh().finally(() => setIsLoading(false));
  }, [refresh]);

  const login = async (username: string, password: string) => {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    if (!res.ok) {
      let message = 'Login failed';
      try {
        const err = await res.json();
        message = err.message || message;
      } catch {
        message = res.status === 502 ? 'API server is unreachable' : `Server error (${res.status})`;
      }
      throw new Error(message);
    }
    const data = await res.json();
    localStorage.setItem('refreshToken', data.refreshToken);
    const user = parseJwt(data.accessToken);
    setAuth({ user, accessToken: data.accessToken });
  };

  const logout = async () => {
    if (auth.accessToken) {
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: { Authorization: `Bearer ${auth.accessToken}` },
      }).catch(() => {});
    }
    localStorage.removeItem('refreshToken');
    setAuth({ user: null, accessToken: null });
  };

  return (
    <AuthContext.Provider value={{ user: auth.user, accessToken: auth.accessToken, isLoading, login, logout, refresh }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
}
