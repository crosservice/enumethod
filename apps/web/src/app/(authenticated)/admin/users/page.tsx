'use client';

import { useEffect, useState, FormEvent } from 'react';
import { useApi } from '@/hooks/useApi';

interface User {
  id: number;
  username: string;
  role: string;
  mustResetPassword: boolean;
  createdAt: string;
}

export default function AdminUsersPage() {
  const { apiFetch } = useApi();
  const [users, setUsers] = useState<User[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);

  // Create form
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState('view');
  const [error, setError] = useState('');

  // Edit form
  const [editRole, setEditRole] = useState('');
  const [editPassword, setEditPassword] = useState('');

  useEffect(() => {
    loadUsers();
  }, []);

  const loadUsers = async () => {
    const res = await apiFetch('/users');
    if (res.ok) setUsers(await res.json());
  };

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    const res = await apiFetch('/users', {
      method: 'POST',
      body: JSON.stringify({ username, password, role }),
    });
    if (res.ok) {
      setShowCreate(false);
      setUsername('');
      setPassword('');
      setRole('view');
      loadUsers();
    } else {
      const err = await res.json();
      setError(err.message || 'Failed to create user');
    }
  };

  const handleEdit = async (id: number) => {
    const body: Record<string, string> = {};
    if (editRole) body.role = editRole;
    if (editPassword) body.password = editPassword;

    const res = await apiFetch(`/users/${id}`, {
      method: 'PATCH',
      body: JSON.stringify(body),
    });
    if (res.ok) {
      setEditingId(null);
      setEditRole('');
      setEditPassword('');
      loadUsers();
    }
  };

  const handleDelete = async (id: number, name: string) => {
    if (!confirm(`Delete user "${name}"?`)) return;
    const res = await apiFetch(`/users/${id}`, { method: 'DELETE' });
    if (res.ok) loadUsers();
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">User Management</h2>
        <button onClick={() => setShowCreate(!showCreate)} className="btn-primary text-sm">
          {showCreate ? 'Cancel' : 'Create User'}
        </button>
      </div>

      {showCreate && (
        <div className="card mb-4">
          <h3 className="font-semibold mb-3">New User</h3>
          {error && <div className="bg-danger/20 text-danger rounded p-2 mb-3 text-sm">{error}</div>}
          <form onSubmit={handleCreate} className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <input
              type="text"
              className="input-field"
              placeholder="Username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              required
              minLength={3}
            />
            <input
              type="password"
              className="input-field"
              placeholder="Password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              minLength={8}
            />
            <select className="input-field" value={role} onChange={(e) => setRole(e.target.value)}>
              <option value="view">View</option>
              <option value="admin">Admin</option>
            </select>
            <button type="submit" className="btn-primary">Create</button>
          </form>
        </div>
      )}

      <div className="card">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-text-secondary">
              <th className="pb-2 pr-4">ID</th>
              <th className="pb-2 pr-4">Username</th>
              <th className="pb-2 pr-4">Role</th>
              <th className="pb-2 pr-4">Must Reset</th>
              <th className="pb-2 pr-4">Created</th>
              <th className="pb-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id} className="border-b border-border/50">
                <td className="py-2 pr-4">{u.id}</td>
                <td className="py-2 pr-4 font-mono">{u.username}</td>
                <td className="py-2 pr-4">
                  <span className={`px-2 py-0.5 rounded text-xs font-medium ${
                    u.role === 'admin' ? 'bg-accent/20 text-accent' : 'bg-border text-text-secondary'
                  }`}>
                    {u.role}
                  </span>
                </td>
                <td className="py-2 pr-4 text-xs">
                  {u.mustResetPassword ? <span className="text-warning">Yes</span> : 'No'}
                </td>
                <td className="py-2 pr-4 text-text-secondary text-xs">
                  {new Date(u.createdAt).toLocaleDateString()}
                </td>
                <td className="py-2">
                  {editingId === u.id ? (
                    <div className="flex gap-2 items-center">
                      <select
                        className="input-field w-auto text-xs"
                        value={editRole || u.role}
                        onChange={(e) => setEditRole(e.target.value)}
                      >
                        <option value="view">View</option>
                        <option value="admin">Admin</option>
                      </select>
                      <input
                        type="password"
                        className="input-field w-32 text-xs"
                        placeholder="New password"
                        value={editPassword}
                        onChange={(e) => setEditPassword(e.target.value)}
                      />
                      <button onClick={() => handleEdit(u.id)} className="text-success text-xs">Save</button>
                      <button onClick={() => setEditingId(null)} className="text-text-secondary text-xs">Cancel</button>
                    </div>
                  ) : (
                    <div className="flex gap-2">
                      <button onClick={() => { setEditingId(u.id); setEditRole(u.role); }} className="text-accent text-xs">
                        Edit
                      </button>
                      <button onClick={() => handleDelete(u.id, u.username)} className="text-danger text-xs">
                        Delete
                      </button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
