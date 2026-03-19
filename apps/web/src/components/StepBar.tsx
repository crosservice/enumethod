'use client';

import { STEP_NAMES, TOTAL_STEPS } from '@/lib/constants';

interface StepBarProps {
  currentStep: number;
  status: string;
}

export function StepBar({ currentStep, status }: StepBarProps) {
  return (
    <div className="card mb-4">
      <div className="flex items-center gap-1">
        {Array.from({ length: TOTAL_STEPS }, (_, i) => {
          const step = i + 1;
          let bg = 'bg-border';
          if (step < currentStep || status === 'completed') bg = 'bg-success';
          else if (step === currentStep && (status === 'running' || status === 'paused')) bg = 'bg-accent animate-pulse';

          return (
            <div key={step} className="flex-1 group relative">
              <div className={`h-2 rounded ${bg} transition-colors`} />
              <div className="absolute bottom-full mb-1 left-1/2 -translate-x-1/2 hidden group-hover:block bg-card border border-border rounded px-2 py-1 text-xs whitespace-nowrap z-10">
                {step}. {STEP_NAMES[step]}
              </div>
            </div>
          );
        })}
      </div>
      <div className="mt-2 text-sm text-text-secondary">
        {status === 'completed' ? (
          'All steps completed'
        ) : status === 'paused' ? (
          `Paused at step ${currentStep}/11 — ${STEP_NAMES[currentStep] || ''}`
        ) : currentStep > 0 ? (
          `Step ${currentStep}/11 — ${STEP_NAMES[currentStep] || ''}`
        ) : (
          'Waiting to start...'
        )}
      </div>
    </div>
  );
}
