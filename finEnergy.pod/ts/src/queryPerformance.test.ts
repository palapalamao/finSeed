import {describe, expect, it, vi} from 'vitest';
import {observeQuery, queryBudgetMs, readQueryServerTiming} from './queryPerformance';

describe('complete query timing', () => {
  it('marks a complete result above 11 seconds as missed and records it once', () => {
    let clock = 100;
    const publish = vi.fn();
    const query = observeQuery('report:profile:cost', () => clock, publish);
    clock += 9_000;
    query.phase('sourceNames');
    clock += 500;
    query.phase('render');
    clock += 1_501;
    query.finish('complete');
    query.finish('cancelled');
    expect(publish).toHaveBeenCalledExactlyOnceWith({
      name: 'report:profile:cost', start: 100, end: 11_101,
      segments: {request: 9_000, sourceNames: 500, render: 1_501},
      outcome: 'complete', missed: true,
    });
  });

  it('keeps an exact 11-second complete result within budget and distinguishes a partial or cancelled query', () => {
    let clock = 0;
    const publish = vi.fn();
    const complete = observeQuery('report', () => clock, publish);
    const partial = observeQuery('report', () => clock, publish);
    const cancelled = observeQuery('report', () => clock, publish);
    clock = queryBudgetMs;
    complete.finish('complete');
    partial.finish('preview');
    clock++;
    cancelled.finish('cancelled');
    expect(publish.mock.calls.map(([m]) => [m.outcome, m.missed])).toEqual([
      ['complete', false], ['preview', false], ['cancelled', true],
    ]);
  });

  it('reads the service phase durations and excludes other header metadata', () => {
    expect(readQueryServerTiming('prepare;dur=10.5, history;dur=20;desc="samples", encode;dur=bad, other;desc="test", calculate;dur=-1')).toEqual({prepare:10.5, history:20});
  });
});
