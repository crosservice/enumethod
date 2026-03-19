'use client';

import { useEffect, useRef, useState } from 'react';

interface LogOutputProps {
  lines: string[];
}

export function LogOutput({ lines }: LogOutputProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const [filter, setFilter] = useState('');

  useEffect(() => {
    if (autoScroll && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [lines, autoScroll]);

  const handleScroll = () => {
    if (!containerRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
    const atBottom = scrollHeight - scrollTop - clientHeight < 50;
    setAutoScroll(atBottom);
  };

  const filteredLines = filter
    ? lines.filter((l) => l.toLowerCase().includes(filter.toLowerCase()))
    : lines;

  return (
    <div className="card flex flex-col" style={{ height: '500px' }}>
      <div className="flex items-center gap-2 mb-2">
        <input
          type="text"
          placeholder="Filter output..."
          className="input-field text-sm flex-1"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <button
          onClick={() => setAutoScroll(true)}
          className={`text-xs px-2 py-1 rounded ${autoScroll ? 'text-accent' : 'text-text-secondary hover:text-text'}`}
        >
          Auto-scroll {autoScroll ? 'ON' : 'OFF'}
        </button>
      </div>
      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="flex-1 overflow-auto bg-bg rounded p-3 font-mono text-xs leading-relaxed"
      >
        {filteredLines.map((line, i) => (
          <div key={i} className={getLineClass(line)}>
            {line}
          </div>
        ))}
        {filteredLines.length === 0 && (
          <div className="text-text-secondary">
            {filter ? 'No matching lines' : 'Waiting for output...'}
          </div>
        )}
      </div>
    </div>
  );
}

function getLineClass(line: string): string {
  if (line.includes('[+]')) return 'text-success';
  if (line.includes('[!]') || line.includes('[SKIP]')) return 'text-warning';
  if (line.includes('[-]')) return 'text-danger';
  if (line.includes('══') || line.includes('Step ')) return 'text-accent font-bold';
  if (line.startsWith('##ENUM_')) return 'text-text-secondary opacity-50';
  return 'text-text';
}
