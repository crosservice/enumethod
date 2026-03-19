'use client';

import { useState, FormEvent } from 'react';

interface ScanFormProps {
  onSubmit: (data: ScanFormData) => void;
  disabled: boolean;
}

export interface ScanFormData {
  targetIp: string;
  domain: string;
  steps: string;
  timing: number;
  wordlist: string;
  skipUdp: boolean;
  skipBruteforce: boolean;
  dryRun: boolean;
}

export function ScanForm({ onSubmit, disabled }: ScanFormProps) {
  const [targetIp, setTargetIp] = useState('');
  const [domain, setDomain] = useState('');
  const [steps, setSteps] = useState('');
  const [timing, setTiming] = useState(4);
  const [wordlist, setWordlist] = useState('');
  const [skipUdp, setSkipUdp] = useState(false);
  const [skipBruteforce, setSkipBruteforce] = useState(false);
  const [dryRun, setDryRun] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    onSubmit({ targetIp, domain, steps, timing, wordlist, skipUdp, skipBruteforce, dryRun });
  };

  return (
    <form onSubmit={handleSubmit} className="card mb-4">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label className="block text-sm text-text-secondary mb-1">Target IP / Hostname *</label>
          <input
            type="text"
            className="input-field"
            value={targetIp}
            onChange={(e) => setTargetIp(e.target.value)}
            placeholder="192.168.1.100"
            required
            disabled={disabled}
          />
        </div>
        <div>
          <label className="block text-sm text-text-secondary mb-1">Domain</label>
          <input
            type="text"
            className="input-field"
            value={domain}
            onChange={(e) => setDomain(e.target.value)}
            placeholder="example.com"
            disabled={disabled}
          />
        </div>
        <div>
          <label className="block text-sm text-text-secondary mb-1">Steps (comma-separated or &quot;all&quot;)</label>
          <input
            type="text"
            className="input-field"
            value={steps}
            onChange={(e) => setSteps(e.target.value)}
            placeholder="all"
            disabled={disabled}
          />
        </div>
      </div>

      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="text-xs text-text-secondary hover:text-accent mt-3 mb-2"
      >
        {expanded ? 'Hide' : 'Show'} advanced options
      </button>

      {expanded && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mt-2">
          <div>
            <label className="block text-sm text-text-secondary mb-1">Timing (0-5)</label>
            <input
              type="number"
              className="input-field"
              value={timing}
              onChange={(e) => setTiming(Number(e.target.value))}
              min={0}
              max={5}
              disabled={disabled}
            />
          </div>
          <div>
            <label className="block text-sm text-text-secondary mb-1">Wordlist path</label>
            <input
              type="text"
              className="input-field"
              value={wordlist}
              onChange={(e) => setWordlist(e.target.value)}
              placeholder="/usr/share/seclists/..."
              disabled={disabled}
            />
          </div>
          <div className="flex flex-col gap-2 justify-end">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={skipUdp} onChange={(e) => setSkipUdp(e.target.checked)} disabled={disabled} />
              <span className="text-text-secondary">Skip UDP scan</span>
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={skipBruteforce} onChange={(e) => setSkipBruteforce(e.target.checked)} disabled={disabled} />
              <span className="text-text-secondary">Skip brute-force</span>
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={dryRun} onChange={(e) => setDryRun(e.target.checked)} disabled={disabled} />
              <span className="text-text-secondary">Dry run</span>
            </label>
          </div>
        </div>
      )}

      <div className="mt-4">
        <button type="submit" className="btn-primary" disabled={disabled || !targetIp.trim()}>
          {disabled ? 'Scan Running...' : 'Start Enumeration'}
        </button>
      </div>
    </form>
  );
}
