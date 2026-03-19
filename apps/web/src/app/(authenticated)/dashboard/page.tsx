'use client';

import { useState, useCallback, useEffect } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { useApi } from '@/hooks/useApi';
import { useWebSocket } from '@/hooks/useWebSocket';
import { ScanForm, ScanFormData } from '@/components/ScanForm';
import { StepBar } from '@/components/StepBar';
import { LogOutput } from '@/components/LogOutput';

export default function DashboardPage() {
  const { user } = useAuth();
  const { apiFetch } = useApi();
  const router = useRouter();
  const searchParams = useSearchParams();

  const [runId, setRunId] = useState<number | null>(null);
  const [status, setStatus] = useState<string>('idle');
  const [currentStep, setCurrentStep] = useState(0);
  const [lines, setLines] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [rerunData, setRerunData] = useState<Partial<ScanFormData> | null>(null);

  // Load previous run arguments if ?rerun=<id> is in the URL
  const rerunId = searchParams.get('rerun');
  useEffect(() => {
    if (!rerunId) return;
    (async () => {
      const res = await apiFetch(`/runs/${rerunId}`);
      if (!res.ok) return;
      const run = await res.json();
      const args = run.arguments || {};
      setRerunData({
        targetIp: run.targetIp,
        domain: run.domain || args.domain || '',
        steps: args.steps || '',
        timing: args.timing ?? 4,
        wordlist: args.wordlist || '',
        skipUdp: args.skipUdp || false,
        skipBruteforce: args.skipBruteforce || false,
      });
    })();
  }, [rerunId]);

  const onCatchup = useCallback((catchupLines: string[], step: number, _command: string | null, catchupStatus: string) => {
    setLines(catchupLines);
    setCurrentStep(step);
    setStatus(catchupStatus);
  }, []);

  const onOutput = useCallback((line: string, step: number, _command: string | null) => {
    setLines((prev) => [...prev, line]);
    setCurrentStep(step);
  }, []);

  const onStatus = useCallback((newStatus: string, step: number) => {
    setStatus(newStatus);
    setCurrentStep(step);
  }, []);

  useWebSocket({
    runId: runId || 0,
    onCatchup,
    onOutput,
    onStatus,
  });

  const handleSubmit = async (data: ScanFormData) => {
    setError('');
    setLines([]);
    setCurrentStep(0);
    setStatus('running');
    setRerunData(null);

    try {
      const res = await apiFetch('/runs', {
        method: 'POST',
        body: JSON.stringify({
          targetIp: data.targetIp,
          domain: data.domain || undefined,
          steps: data.steps || undefined,
          timing: data.timing,
          wordlist: data.wordlist || undefined,
          skipUdp: data.skipUdp,
          skipBruteforce: data.skipBruteforce,
          dryRun: data.dryRun,
        }),
      });

      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.message || 'Failed to start scan');
      }

      const run = await res.json();
      setRunId(run.id);
      // Clean rerun param from URL
      router.replace('/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start scan');
      setStatus('idle');
    }
  };

  const handlePause = async () => {
    if (!runId) return;
    await apiFetch(`/runs/${runId}/pause`, { method: 'POST' });
  };

  const handleResume = async () => {
    if (!runId) return;
    await apiFetch(`/runs/${runId}/resume`, { method: 'POST' });
    setStatus('running');
  };

  const handleCancel = async () => {
    if (!runId) return;
    await apiFetch(`/runs/${runId}/cancel`, { method: 'POST' });
  };

  const isRunning = status === 'running' || status === 'paused';
  const isAdmin = user?.role === 'admin';

  return (
    <div>
      <h2 className="text-xl font-bold mb-4">Dashboard</h2>

      {error && (
        <div className="bg-danger/20 text-danger border border-danger/30 rounded p-3 mb-4 text-sm">
          {error}
        </div>
      )}

      {isAdmin && (
        <ScanForm onSubmit={handleSubmit} disabled={isRunning} initialData={rerunData} />
      )}

      {!isAdmin && !isRunning && (
        <div className="card mb-4 text-text-secondary text-sm">
          You have view-only access. Contact an admin to start scans.
        </div>
      )}

      {(isRunning || status === 'completed' || status === 'failed' || status === 'cancelled') && (
        <>
          <StepBar currentStep={currentStep} status={status} />

          <LogOutput lines={lines} />

          {isRunning && isAdmin && (
            <div className="flex gap-2 mt-4">
              {status === 'running' ? (
                <button onClick={handlePause} className="btn-secondary">
                  Pause
                </button>
              ) : (
                <button onClick={handleResume} className="btn-primary">
                  Resume
                </button>
              )}
              <button onClick={handleCancel} className="btn-danger">
                Cancel
              </button>
            </div>
          )}

          {(status === 'completed' || status === 'failed' || status === 'cancelled') && runId && (
            <div className="flex gap-2 mt-4">
              <button
                onClick={() => router.push(`/runs/${runId}`)}
                className="btn-primary"
              >
                View Details
              </button>
              <span className={`px-3 py-2 rounded text-sm font-medium ${
                status === 'completed' ? 'text-success' : status === 'failed' ? 'text-danger' : 'text-warning'
              }`}>
                {status.charAt(0).toUpperCase() + status.slice(1)}
              </span>
            </div>
          )}
        </>
      )}
    </div>
  );
}
