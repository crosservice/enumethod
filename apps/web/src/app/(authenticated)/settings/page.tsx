'use client';

import { useState, useEffect, FormEvent } from 'react';
import { useAuth } from '@/lib/auth-context';
import { useApi } from '@/hooks/useApi';

export default function SettingsPage() {
  const { user } = useAuth();
  const { apiFetch } = useApi();

  // Password change
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [pwMsg, setPwMsg] = useState('');
  const [pwError, setPwError] = useState('');

  // AI prompt template
  const [promptTemplate, setPromptTemplate] = useState('');
  const [promptMsg, setPromptMsg] = useState('');
  const [promptError, setPromptError] = useState('');

  useEffect(() => {
    if (user?.role === 'admin') {
      loadSettings();
    }
  }, [user]);

  const loadSettings = async () => {
    const res = await apiFetch('/settings');
    if (res.ok) {
      const settings = await res.json();
      const aiPrompt = settings.find((s: { key: string }) => s.key === 'ai_prompt_template');
      if (aiPrompt) setPromptTemplate(aiPrompt.value);
    }
  };

  const handlePasswordChange = async (e: FormEvent) => {
    e.preventDefault();
    setPwMsg('');
    setPwError('');

    if (newPassword !== confirmPassword) {
      setPwError('Passwords do not match');
      return;
    }
    if (newPassword.length < 8) {
      setPwError('Password must be at least 8 characters');
      return;
    }

    const res = await apiFetch('/users/change-password', {
      method: 'POST',
      body: JSON.stringify({ currentPassword, newPassword, confirmPassword }),
    });

    if (res.ok) {
      setPwMsg('Password changed successfully');
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
    } else {
      const err = await res.json();
      setPwError(err.message || 'Failed to change password');
    }
  };

  const handleSavePrompt = async () => {
    setPromptMsg('');
    setPromptError('');

    const res = await apiFetch('/settings/ai_prompt_template', {
      method: 'PUT',
      body: JSON.stringify({ value: promptTemplate }),
    });

    if (res.ok) {
      setPromptMsg('Prompt template saved');
    } else {
      const err = await res.json();
      setPromptError(err.message || 'Failed to save');
    }
  };

  return (
    <div>
      <h2 className="text-xl font-bold mb-4">Settings</h2>

      {user?.mustReset && (
        <div className="bg-warning/20 text-warning border border-warning/30 rounded p-3 mb-4 text-sm">
          You must change your password before continuing.
        </div>
      )}

      {/* Password Change */}
      <div className="card mb-6">
        <h3 className="text-lg font-semibold mb-4">Change Password</h3>
        {pwMsg && <div className="bg-success/20 text-success rounded p-2 mb-3 text-sm">{pwMsg}</div>}
        {pwError && <div className="bg-danger/20 text-danger rounded p-2 mb-3 text-sm">{pwError}</div>}
        <form onSubmit={handlePasswordChange} className="space-y-3 max-w-sm">
          <div>
            <label className="block text-sm text-text-secondary mb-1">Current Password</label>
            <input
              type="password"
              className="input-field"
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
              required
            />
          </div>
          <div>
            <label className="block text-sm text-text-secondary mb-1">New Password</label>
            <input
              type="password"
              className="input-field"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              required
              minLength={8}
            />
          </div>
          <div>
            <label className="block text-sm text-text-secondary mb-1">Confirm New Password</label>
            <input
              type="password"
              className="input-field"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
            />
          </div>
          <button type="submit" className="btn-primary">
            Change Password
          </button>
        </form>
      </div>

      {/* AI Prompt Template (admin only) */}
      {user?.role === 'admin' && (
        <div className="card">
          <h3 className="text-lg font-semibold mb-4">AI Prompt Template</h3>
          <p className="text-text-secondary text-sm mb-3">
            Available variables: {'{{target_ip}}'}, {'{{domain}}'}, {'{{scan_date}}'}, {'{{run_output}}'}, {'{{cve_data}}'}
          </p>
          {promptMsg && <div className="bg-success/20 text-success rounded p-2 mb-3 text-sm">{promptMsg}</div>}
          {promptError && <div className="bg-danger/20 text-danger rounded p-2 mb-3 text-sm">{promptError}</div>}
          <textarea
            className="input-field font-mono text-sm"
            rows={15}
            value={promptTemplate}
            onChange={(e) => setPromptTemplate(e.target.value)}
          />
          <button onClick={handleSavePrompt} className="btn-primary mt-3">
            Save Template
          </button>
        </div>
      )}
    </div>
  );
}
