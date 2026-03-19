'use client';

import { useEffect, useRef, useCallback, useState } from 'react';
import { io, Socket } from 'socket.io-client';
import { useAuth } from '@/lib/auth-context';

interface UseWebSocketOptions {
  runId: number;
  onOutput?: (line: string, step: number, command: string | null) => void;
  onStatus?: (status: string, step: number) => void;
  onCatchup?: (lines: string[], step: number, command: string | null, status: string) => void;
}

export function useWebSocket({ runId, onOutput, onStatus, onCatchup }: UseWebSocketOptions) {
  const { accessToken } = useAuth();
  const socketRef = useRef<Socket | null>(null);
  const [connected, setConnected] = useState(false);

  const disconnect = useCallback(() => {
    if (socketRef.current) {
      socketRef.current.disconnect();
      socketRef.current = null;
      setConnected(false);
    }
  }, []);

  useEffect(() => {
    if (!accessToken || !runId) return;

    const socket = io('/ws/runs', {
      auth: { token: accessToken },
      transports: ['websocket'],
    });

    socketRef.current = socket;

    socket.on('connect', () => {
      setConnected(true);
      socket.emit('subscribe', { runId });
    });

    socket.on('catchup', (data) => {
      onCatchup?.(data.lines, data.step, data.command, data.status);
    });

    socket.on('output', (data) => {
      onOutput?.(data.line, data.step, data.command);
    });

    socket.on('status', (data) => {
      onStatus?.(data.status, data.step);
    });

    socket.on('disconnect', () => {
      setConnected(false);
    });

    return () => {
      socket.disconnect();
    };
  }, [accessToken, runId, onOutput, onStatus, onCatchup]);

  return { connected, disconnect };
}
