export const queryBudgetMs = 11_000;

type QueryPhase = 'request' | 'decode' | 'sourceNames' | 'render';
type QueryOutcome = 'complete' | 'preview' | 'cancelled' | 'failed';
type QuerySegments = Partial<Record<QueryPhase, number>>;

interface QueryMeasurement {
  name: string;
  start: number;
  end: number;
  segments: QuerySegments;
  outcome: QueryOutcome;
  missed: boolean;
}

export function recordQueryPerformance(name: 'operation' | 'transport', start: number, end: number, detail: object) {
  const key = `finenergy.query.${name}`;
  if (performance.getEntriesByName(key, 'measure').length >= 128) performance.clearMeasures(key);
  performance.measure(key, {start, end, detail});
}

export function observeQuery(name: string, now = () => performance.now(), publish = (measurement: QueryMeasurement) => {
  recordQueryPerformance('operation', measurement.start, measurement.end, measurement);
}) {
  const start = now();
  const segments: QuerySegments = {};
  let phase: QueryPhase = 'request';
  let phaseStart = start;
  let finished = false;

  const closeSegment = (at: number) => {
    segments[phase] = (segments[phase] ?? 0) + at - phaseStart;
    phaseStart = at;
  };

  return {
    start,
    phase(next: QueryPhase) {
      if (finished || phase === next) return;
      closeSegment(now());
      phase = next;
    },
    finish(outcome: QueryOutcome) {
      if (finished) return;
      finished = true;
      const end = now();
      closeSegment(end);
      publish({name, start, end, segments, outcome, missed: end - start > queryBudgetMs});
    },
  };
}

const serverPhases = new Set(['prepare', 'history', 'nativeRead', 'clean', 'normalize', 'calculate', 'encode', 'total']);

export function readQueryServerTiming(header: string | null): Record<string, number> {
  const phases: Record<string, number> = {};
  for (const item of (header ?? '').split(',')) {
    const match = /^(\w+)\s*;\s*dur=(\d+(?:\.\d+)?)(?:;|$)/.exec(item.trim());
    if (match && serverPhases.has(match[1])) phases[match[1]] = Number(match[2]);
  }
  return phases;
}

export function afterQueryPaint(callback: () => void) {
  if (document.visibilityState !== 'visible') {
    setTimeout(callback, 0);
    return;
  }
  requestAnimationFrame(() => requestAnimationFrame(callback));
}
