'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/lib/auth-context';
import { useApi } from '@/hooks/useApi';

interface Run {
  id: number;
  targetIp: string;
  domain: string;
  status: string;
  currentStep: number;
  startedAt: string | null;
  finishedAt: string | null;
}

export default function RunsPage() {
  const { accessToken } = useAuth();
  const { apiFetch } = useApi();
  const [runs, setRuns] = useState<Run[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const limit = 20;
  const authUrl = (path: string) => `${path}${path.includes('?') ? '&' : '?'}token=${accessToken}`;

  const handleDelete = async (id: number, target: string) => {
    if (!confirm(`Delete run #${id} (${target})? This removes all output files and cannot be undone.`)) return;
    const res = await apiFetch(`/runs/${id}`, { method: 'DELETE' });
    if (res.ok) loadRuns();
  };

  useEffect(() => {
    loadRuns();
  }, [page]);

  const loadRuns = async () => {
    setLoading(true);
    try {
      const res = await apiFetch(`/runs?page=${page}&limit=${limit}`);
      if (res.ok) {
        const data = await res.json();
        setRuns(data.data);
        setTotal(data.total);
      }
    } finally {
      setLoading(false);
    }
  };

  const totalPages = Math.ceil(total / limit);

  const statusBadge = (status: string) => {
    const colors: Record<string, string> = {
      running: 'bg-accent/20 text-accent',
      paused: 'bg-warning/20 text-warning',
      completed: 'bg-success/20 text-success',
      failed: 'bg-danger/20 text-danger',
      cancelled: 'bg-border text-text-secondary',
      pending: 'bg-border text-text-secondary',
    };
    return (
      <span className={`px-2 py-0.5 rounded text-xs font-medium ${colors[status] || colors.pending}`}>
        {status}
      </span>
    );
  };

  const formatDate = (d: string | null) => {
    if (!d) return '—';
    return new Date(d).toLocaleString();
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Past Runs</h2>
        <button onClick={loadRuns} className="btn-secondary text-sm">
          Refresh
        </button>
      </div>

      <div className="card overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-text-secondary">
              <th className="pb-2 pr-4">ID</th>
              <th className="pb-2 pr-4">Target</th>
              <th className="pb-2 pr-4">Domain</th>
              <th className="pb-2 pr-4">Status</th>
              <th className="pb-2 pr-4">Step</th>
              <th className="pb-2 pr-4">Started</th>
              <th className="pb-2 pr-4">Finished</th>
              <th className="pb-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan={8} className="py-8 text-center text-text-secondary">Loading...</td>
              </tr>
            ) : runs.length === 0 ? (
              <tr>
                <td colSpan={8} className="py-8 text-center text-text-secondary">No runs yet</td>
              </tr>
            ) : (
              runs.map((run) => (
                <tr key={run.id} className="border-b border-border/50 hover:bg-bg/50">
                  <td className="py-2 pr-4">{run.id}</td>
                  <td className="py-2 pr-4 font-mono">{run.targetIp}</td>
                  <td className="py-2 pr-4">{run.domain || '—'}</td>
                  <td className="py-2 pr-4">{statusBadge(run.status)}</td>
                  <td className="py-2 pr-4">{run.currentStep}/11</td>
                  <td className="py-2 pr-4 text-text-secondary text-xs">{formatDate(run.startedAt)}</td>
                  <td className="py-2 pr-4 text-text-secondary text-xs">{formatDate(run.finishedAt)}</td>
                  <td className="py-2">
                    <div className="flex gap-2">
                      <Link href={`/runs/${run.id}`} className="text-accent hover:text-accent-hover text-xs">
                        View
                      </Link>
                      {run.status === 'completed' && (
                        <>
                          <a href={authUrl(`/api/runs/${run.id}/report`)} target="_blank" className="text-accent hover:text-accent-hover text-xs">
                            Report
                          </a>
                          <a href={authUrl(`/api/runs/${run.id}/export`)} className="text-accent hover:text-accent-hover text-xs">
                            ZIP
                          </a>
                        </>
                      )}
                      {run.status !== 'running' && run.status !== 'paused' && (
                        <button
                          onClick={() => handleDelete(run.id, run.targetIp)}
                          className="text-danger hover:text-danger/80 text-xs"
                        >
                          Delete
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>

        {totalPages > 1 && (
          <div className="flex items-center justify-between mt-4 pt-4 border-t border-border">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              className="btn-secondary text-xs"
            >
              Previous
            </button>
            <span className="text-sm text-text-secondary">
              Page {page} of {totalPages}
            </span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
              className="btn-secondary text-xs"
            >
              Next
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
