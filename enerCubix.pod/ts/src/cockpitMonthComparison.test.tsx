import {afterEach,expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {CockpitDates,cockpitComparisonForPreset,type CockpitDateDraft} from './CockpitDates';
import {cockpitComparisonText} from './cockpitMetrics';
import {freshCockpitRequest} from './cockpitAutoRefresh';
import {initializeLocale} from './i18n';
import type {CockpitMetric,CockpitSnapshot} from './cockpitTypes';
import fixture from '../tests/fixtures/cockpit-metrics-response.json';

afterEach(()=>initializeLocale('zh-CN'));

it.each(['zh-CN','en-US'])('presents a labelled monthly comparison and its calendar basis in %s',language=>{
 initializeLocale(language);
 const draft:CockpitDateDraft={period:'day',comparison:{mode:'previousMonth'}};
 const html=renderToStaticMarkup(<CockpitDates preset="thisMonth" draft={draft} onChange={()=>{}}/>);
 expect(html).toContain(language==='zh-CN'?'环比（上月对应区间）':'Month over month');
 expect(html).toContain(language==='zh-CN'?'月中对齐同日同刻':'the same day and local time');
});

it('keeps month comparison for monthly and custom ranges, and resets it for incompatible presets',()=>{
 const comparison={mode:'previousMonth' as const};
 expect(cockpitComparisonForPreset(comparison,'thisMonth')).toBe(comparison);
 expect(cockpitComparisonForPreset(comparison,'custom')).toBe(comparison);
 expect(cockpitComparisonForPreset(comparison,'today')).toEqual({mode:'presetDefault'});
 expect(cockpitComparisonForPreset(comparison,'thisYear')).toEqual({mode:'presetDefault'});
 const custom={mode:'custom' as const,from:'2025-01-01T00:00:00Z',to:'2025-02-01T00:00:00Z'};
 expect(cockpitComparisonForPreset(custom,'thisYear')).toBe(custom);
});

it.each(['zh-CN','en-US'])('distinguishes month-over-month from year-over-year without recalculating rates in %s',language=>{
 initializeLocale(language);
 const metric=structuredClone(fixture.modules.kpis.data.values[0]) as unknown as CockpitMetric&{comparison:NonNullable<CockpitMetric['comparison']>};
 metric.comparison.kind='previousMonthSameElapsedCalendar';
 metric.comparison.reasonCodes=['DURATION_DIFFERENCE'];metric.comparison.durationDifferenceSeconds=86400;
 const before=structuredClone(metric);
 expect(cockpitComparisonText(metric)).toContain(language==='zh-CN'?'环比 +25%':'Month over month +25%');
 expect(metric).toEqual(before);
 metric.comparison.kind='yearSameElapsedCalendar';
 expect(cockpitComparisonText(metric)).toContain(language==='zh-CN'?'同比 +25%':'Year over year +25%');
});

it.each(['zh-CN','en-US'])('identifies unavailable monthly comparisons and never turns a zero reference into a rate in %s',language=>{
 initializeLocale(language);
 const metric=structuredClone(fixture.modules.kpis.data.values[0]) as unknown as CockpitMetric&{comparison:NonNullable<CockpitMetric['comparison']>};
 Object.assign(metric.comparison,{kind:'previousMonthSameElapsedCalendar',reference:0,changeRate:null,reasonCodes:['ZERO_REFERENCE']});
 const text=cockpitComparisonText(metric);
 expect(text).toContain(language==='zh-CN'?'环比':'Month over month');
 expect(text).toContain(language==='zh-CN'?'参照期为零':'zero');expect(text).not.toContain('%');
});

it('retains the monthly mode when refreshing a relative month, with a fresh server cutoff',()=>{
 const snapshot=structuredClone(fixture) as unknown as CockpitSnapshot;
 snapshot.context.time.preset='thisMonth';snapshot.context.comparison={mode:'previousMonth'};
 const before=structuredClone(snapshot),request=freshCockpitRequest(snapshot,'monthly-refresh');
 expect(request.comparison).toEqual({mode:'previousMonth'});
 expect(request.time).toEqual({preset:'thisMonth',period:snapshot.context.time.period});
 expect(request.asOf).toBeUndefined();expect(snapshot).toEqual(before);
});
