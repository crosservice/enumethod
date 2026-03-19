'use client';

import { useEffect, useState } from 'react';
import { useApi } from '@/hooks/useApi';

interface Credential {
  id: number;
  name: string;
  provider: string;
  maskedKey: string;
  createdAt: string;
  updatedAt: string;
}

export default function AdminCredentialsPage() {
  const { apiFetch } = useApi();
  const [credentials, setCredentials] = useState<Credential[]>([]);
  const [showAdd, setShowAdd] = useState(false);
  const [name, setName] = useState('');
  const [provider, setProvider] = useState<'claude' | 'openai'>('claude');
  const [apiKey, setApiKey] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    loadCredentials();
  }, []);

  const loadCredentials = async () => {
    const res = await apiFetch('/credentials');
    if (res.ok) setCredentials(await res.json());
  };

  const handleAdd = async () => {
    setError('');
    if (!name.trim() || !apiKey.trim()) {
      setError('Name and API key are required');
      return;
    }
    const res = await apiFetch('/credentials', {
      method: 'POST',
      body: JSON.stringify({ name, provider, apiKey }),
    });
    if (res.ok) {
      setShowAdd(false);
      setName('');
      setApiKey('');
      loadCredentials();
    } else {
      const err = await res.json();
      setError(err.message || 'Failed to add credential');
    }
  };

  const handleDelete = async (id: number, credName: string) => {
    if (!confirm(`Delete credential "${credName}"?`)) return;
    const res = await apiFetch(`/credentials/${id}`, { method: 'DELETE' });
    if (res.ok) loadCredentials();
  };

  const claudeCreds = credentials.filter((c) => c.provider === 'claude');
  const openaiCreds = credentials.filter((c) => c.provider === 'openai');

  const ProviderCard = ({ title, creds, prov }: { title: string; creds: Credential[]; prov: 'claude' | 'openai' }) => (
    <div className="card">
      <h3 className="font-semibold mb-3">{title}</h3>
      {creds.length === 0 ? (
        <p className="text-text-secondary text-sm mb-3">No API key configured</p>
      ) : (
        <div className="space-y-2 mb-3">
          {creds.map((c) => (
            <div key={c.id} className="flex items-center justify-between bg-bg rounded px-3 py-2">
              <div>
                <div className="text-sm font-medium">{c.name}</div>
                <div className="text-xs text-text-secondary font-mono">{c.maskedKey}</div>
              </div>
              <button onClick={() => handleDelete(c.id, c.name)} className="text-danger text-xs">
                Delete
              </button>
            </div>
          ))}
        </div>
      )}
      <button
        onClick={() => {
          setProvider(prov);
          setShowAdd(true);
        }}
        className="btn-secondary text-xs"
      >
        Add {title} Key
      </button>
    </div>
  );

  return (
    <div>
      <h2 className="text-xl font-bold mb-4">API Credentials</h2>

      {showAdd && (
        <div className="card mb-4">
          <h3 className="font-semibold mb-3">Add API Key — {provider === 'claude' ? 'Claude' : 'OpenAI'}</h3>
          {error && <div className="bg-danger/20 text-danger rounded p-2 mb-3 text-sm">{error}</div>}
          <div className="space-y-3 max-w-md">
            <input
              type="text"
              className="input-field"
              placeholder="Name (e.g., 'Production Key')"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
            <input
              type="password"
              className="input-field"
              placeholder="API Key"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
            />
            <div className="flex gap-2">
              <button onClick={handleAdd} className="btn-primary text-sm">Save</button>
              <button onClick={() => setShowAdd(false)} className="btn-secondary text-sm">Cancel</button>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <ProviderCard title="Claude" creds={claudeCreds} prov="claude" />
        <ProviderCard title="OpenAI" creds={openaiCreds} prov="openai" />
      </div>
    </div>
  );
}
