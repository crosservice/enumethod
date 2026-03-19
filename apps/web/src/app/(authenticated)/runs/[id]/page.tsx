'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { useApi } from '@/hooks/useApi';

interface RunDetail {
  id: number;
  targetIp: string;
  domain: string;
  arguments: Record<string, unknown>;
  status: string;
  currentStep: number;
  currentCommand: string | null;
  startedAt: string | null;
  finishedAt: string | null;
}

interface RunOutput {
  id: number;
  stepNumber: number;
  commandName: string;
  outputText: string;
  exitCode: number | null;
}

interface Assessment {
  id: number;
  provider: string;
  response: string;
  severitySummary: Record<string, unknown> | null;
  createdAt: string;
}

export default function RunDetailPage() {
  const params = useParams();
  const runId = params.id as string;
  const { user } = useAuth();
  const { apiFetch } = useApi();

  const [run, setRun] = useState<RunDetail | null>(null);
  const [outputs, setOutputs] = useState<RunOutput[]>([]);
  const [assessment, setAssessment] = useState<Assessment | null>(null);
  const [activeTab, setActiveTab] = useState<'output' | 'report' | 'ai'>('output');
  const [search, setSearch] = useState('');
  const [expandedCmd, setExpandedCmd] = useState<number | null>(null);
  const [assessing, setAssessing] = useState(false);
  const [assessError, setAssessError] = useState('');
  const [provider, setProvider] = useState<'claude' | 'openai'>('claude');

  useEffect(() => {
    loadRun();
    loadOutputs();
    loadAssessment();
  }, [runId]);

  const loadRun = async () => {
    const res = await apiFetch(`/runs/${runId}`);
    if (res.ok) setRun(await res.json());
  };

  const loadOutputs = async () => {
    const res = await apiFetch(`/runs/${runId}/outputs`);
    if (res.ok) setOutputs(await res.json());
  };

  const loadAssessment = async () => {
    const res = await apiFetch(`/runs/${runId}/assessment`);
    if (res.ok) setAssessment(await res.json());
  };

  const triggerAssessment = async () => {
    setAssessing(true);
    setAssessError('');
    try {
      const res = await apiFetch(`/runs/${runId}/assess`, {
        method: 'POST',
        body: JSON.stringify({ provider }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.message);
      }
      const data = await res.json();
      setAssessment(data);
    } catch (err) {
      setAssessError(err instanceof Error ? err.message : 'Assessment failed');
    } finally {
      setAssessing(false);
    }
  };

  const filteredOutputs = search
    ? outputs.filter(
        (o) =>
          o.commandName.toLowerCase().includes(search.toLowerCase()) ||
          o.outputText.toLowerCase().includes(search.toLowerCase()),
      )
    : outputs;

  const formatDate = (d: string | null) => (d ? new Date(d).toLocaleString() : '—');

  const statusColor: Record<string, string> = {
    running: 'text-accent',
    paused: 'text-warning',
    completed: 'text-success',
    failed: 'text-danger',
    cancelled: 'text-text-secondary',
  };

  if (!run) {
    return <div className="text-text-secondary">Loading...</div>;
  }

  return (
    <div>
      <h2 className="text-xl font-bold mb-4">Run #{run.id}</h2>

      {/* Metadata */}
      <div className="card mb-4 grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
        <div>
          <div className="text-text-secondary">Target</div>
          <div className="font-mono">{run.targetIp}</div>
        </div>
        <div>
          <div className="text-text-secondary">Domain</div>
          <div>{run.domain || '—'}</div>
        </div>
        <div>
          <div className="text-text-secondary">Status</div>
          <div className={`font-medium ${statusColor[run.status] || ''}`}>
            {run.status}
          </div>
        </div>
        <div>
          <div className="text-text-secondary">Step</div>
          <div>{run.currentStep}/11</div>
        </div>
        <div>
          <div className="text-text-secondary">Started</div>
          <div className="text-xs">{formatDate(run.startedAt)}</div>
        </div>
        <div>
          <div className="text-text-secondary">Finished</div>
          <div className="text-xs">{formatDate(run.finishedAt)}</div>
        </div>
        {run.status === 'completed' && (
          <>
            <div>
              <a href={`/api/runs/${run.id}/report`} target="_blank" className="text-accent hover:text-accent-hover text-xs">
                View Report
              </a>
            </div>
            <div>
              <a href={`/api/runs/${run.id}/export`} className="text-accent hover:text-accent-hover text-xs">
                Download ZIP
              </a>
            </div>
          </>
        )}
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-4 border-b border-border">
        {(['output', 'report', 'ai'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
              activeTab === tab
                ? 'border-accent text-accent'
                : 'border-transparent text-text-secondary hover:text-text'
            }`}
          >
            {tab === 'output' ? 'Output' : tab === 'report' ? 'Report' : 'AI Assessment'}
          </button>
        ))}
      </div>

      {/* Output tab */}
      {activeTab === 'output' && (
        <div className="card">
          <input
            type="text"
            placeholder="Search commands or output..."
            className="input-field mb-4"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <div className="space-y-1">
            {filteredOutputs.length === 0 ? (
              <div className="text-text-secondary text-sm py-4 text-center">
                {search ? 'No matching commands' : 'No output recorded'}
              </div>
            ) : (
              filteredOutputs.map((output) => (
                <div key={output.id} className="border border-border/50 rounded">
                  <button
                    onClick={() => setExpandedCmd(expandedCmd === output.id ? null : output.id)}
                    className="w-full flex items-center justify-between px-3 py-2 text-sm hover:bg-bg/50 transition-colors"
                  >
                    <span className="flex items-center gap-2">
                      <span className="text-text-secondary">Step {output.stepNumber}</span>
                      <span className="font-medium">{output.commandName}</span>
                    </span>
                    <span className={`text-xs ${
                      output.exitCode === 0 ? 'text-success' :
                      output.exitCode === -1 ? 'text-warning' :
                      output.exitCode !== null ? 'text-danger' : 'text-text-secondary'
                    }`}>
                      {output.exitCode === -1 ? 'skipped' :
                       output.exitCode !== null ? `exit ${output.exitCode}` : 'running'}
                    </span>
                  </button>
                  {expandedCmd === output.id && (
                    <pre className="px-3 py-2 bg-bg text-xs font-mono overflow-auto max-h-96 border-t border-border/50">
                      {output.outputText || '(no output)'}
                    </pre>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      )}

      {/* Report tab */}
      {activeTab === 'report' && (
        <div className="card">
          {run.status === 'completed' ? (
            <iframe
              src={`/api/runs/${run.id}/report`}
              className="w-full border-0 rounded"
              style={{ height: '700px' }}
              title="Enumeration Report"
            />
          ) : (
            <div className="text-text-secondary text-sm py-8 text-center">
              Report available after scan completes
            </div>
          )}
        </div>
      )}

      {/* AI Assessment tab */}
      {activeTab === 'ai' && (
        <div className="card">
          {assessment ? (
            <div>
              <div className="flex items-center justify-between mb-4">
                <div className="text-sm text-text-secondary">
                  Provider: {assessment.provider} | Generated: {formatDate(assessment.createdAt)}
                </div>
                {user?.role === 'admin' && (
                  <button onClick={triggerAssessment} className="btn-secondary text-xs" disabled={assessing}>
                    Re-analyze
                  </button>
                )}
              </div>
              {assessment.severitySummary && (
                <div className="flex gap-3 mb-4">
                  {['critical', 'high', 'medium', 'low', 'info'].map((sev) => {
                    const count = (assessment.severitySummary as Record<string, number>)?.[sev] || 0;
                    const colors: Record<string, string> = {
                      critical: 'bg-danger/20 text-danger',
                      high: 'bg-danger/10 text-danger',
                      medium: 'bg-warning/20 text-warning',
                      low: 'bg-accent/20 text-accent',
                      info: 'bg-border text-text-secondary',
                    };
                    return (
                      <div key={sev} className={`px-3 py-1 rounded text-sm ${colors[sev]}`}>
                        {sev}: {count}
                      </div>
                    );
                  })}
                </div>
              )}
              <div className="prose prose-invert max-w-none">
                <pre className="bg-bg rounded p-4 text-sm font-mono whitespace-pre-wrap overflow-auto">
                  {assessment.response}
                </pre>
              </div>
            </div>
          ) : (
            <div className="text-center py-8">
              {user?.role === 'admin' ? (
                <div>
                  <p className="text-text-secondary text-sm mb-4">No AI assessment yet</p>
                  {assessError && (
                    <div className="bg-danger/20 text-danger border border-danger/30 rounded p-3 mb-4 text-sm max-w-md mx-auto">
                      {assessError}
                    </div>
                  )}
                  <div className="flex items-center justify-center gap-3">
                    <select
                      value={provider}
                      onChange={(e) => setProvider(e.target.value as 'claude' | 'openai')}
                      className="input-field w-auto"
                    >
                      <option value="claude">Claude</option>
                      <option value="openai">OpenAI</option>
                    </select>
                    <button onClick={triggerAssessment} className="btn-primary" disabled={assessing}>
                      {assessing ? 'Analyzing...' : 'Analyze with AI'}
                    </button>
                  </div>
                </div>
              ) : (
                <p className="text-text-secondary text-sm">No assessment available. Admin can trigger analysis.</p>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
