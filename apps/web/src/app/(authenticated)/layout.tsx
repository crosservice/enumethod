'use client';

import { useEffect } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import Link from 'next/link';

const navItems = [
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/runs', label: 'Past Runs' },
  { href: '/settings', label: 'Settings' },
];

const adminNavItems = [
  { href: '/admin/users', label: 'Users' },
  { href: '/admin/credentials', label: 'Credentials' },
];

export default function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  const { user, isLoading, logout } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (!isLoading && !user) {
      router.push('/login');
    }
    if (!isLoading && user?.mustReset && pathname !== '/settings') {
      router.push('/settings');
    }
  }, [user, isLoading, router, pathname]);

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-text-secondary">Loading...</div>
      </div>
    );
  }

  if (!user) return null;

  return (
    <div className="min-h-screen flex">
      <aside className="w-56 bg-card border-r border-border flex flex-col">
        <div className="p-4 border-b border-border">
          <h1 className="text-lg font-bold">
            <span className="text-accent">enum</span>ethod
          </h1>
        </div>
        <nav className="flex-1 p-3 space-y-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`block px-3 py-2 rounded text-sm transition-colors ${
                pathname === item.href
                  ? 'bg-accent/20 text-accent'
                  : 'text-text-secondary hover:text-text hover:bg-bg'
              }`}
            >
              {item.label}
            </Link>
          ))}
          {user.role === 'admin' && (
            <>
              <div className="pt-3 pb-1 px-3 text-xs text-text-secondary uppercase tracking-wider">
                Admin
              </div>
              {adminNavItems.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`block px-3 py-2 rounded text-sm transition-colors ${
                    pathname === item.href
                      ? 'bg-accent/20 text-accent'
                      : 'text-text-secondary hover:text-text hover:bg-bg'
                  }`}
                >
                  {item.label}
                </Link>
              ))}
            </>
          )}
        </nav>
        <div className="p-3 border-t border-border">
          <div className="text-xs text-text-secondary mb-2">
            {user.username} ({user.role})
          </div>
          <button
            onClick={logout}
            className="text-xs text-text-secondary hover:text-danger transition-colors"
          >
            Sign Out
          </button>
        </div>
      </aside>
      <main className="flex-1 p-6 overflow-auto">
        {children}
      </main>
    </div>
  );
}
