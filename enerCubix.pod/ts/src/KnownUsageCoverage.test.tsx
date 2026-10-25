import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {describe,it,expect} from 'vitest';
import {ReportView} from './ReportView';
import type {ReportSnapshot} from './types';
import {coverageGroups} from './knownUsageCoverage';

export function coverageSnapshot():ReportSnapshot{
 return {title:'能耗概况',project:'test',generatedAt:'2026-10-25T03:00:00+08:00',request:{kind:'profile',dimension:'metering',nodeIds:['m'],from:'2026-10-25T00:00:00+08:00',to:'2026-10-25T03:00:00+08:00',period:'hour',metric:'energy',perArea:false},display:{objects:{m:'总电表'},sources:{p:'电能'},meterKinds:{m:'totalMeter'}},result:{kind:'profile',from:'2026-10-25T00:00:00+08:00',to:'2026-10-25T03:00:00+08:00',period:'hour',rows:[],series:[],summary:{},warnings:[],extra:{dimension:'metering',knownUsage:{basis:'closedSourceIntervals',detailsTruncated:false,sourceUsage:[{nodeId:'m',pointId:'p',unit:'kWh',from:'2026-10-25T00:00:00+08:00',to:'2026-10-25T01:00:00+08:00',knownValue:null,knownQuality:'missing',knownValueType:'null',coveredSeconds:0,intervalCount:0,intervals:[]}]}}}};
}
describe('readable coverage presentation',()=>{
 it('sorts and merges adjacent gaps without counting future periods as missing',()=>{
  const snapshot=coverageSnapshot();snapshot.generatedAt='2026-10-25T02:00:00+08:00';
  const usage=snapshot.result.extra!.knownUsage as {sourceUsage:Record<string,unknown>[]};const base=usage.sourceUsage[0];
  usage.sourceUsage=[{...base,from:'2026-10-25T02:00:00+08:00',to:'2026-10-25T03:00:00+08:00'},{...base,from:'2026-10-25T01:00:00+08:00',to:'2026-10-25T02:00:00+08:00'},base];
  const before=structuredClone(snapshot),group=coverageGroups(snapshot)[0];
  expect(group.periods.map(p=>[p.status,p.slots])).toEqual([['missing',2],['future',1]]);
  expect(group.periods[0].from).toBe(base.from);expect(group.periods[0].to).toBe('2026-10-25T02:00:00+08:00');expect(snapshot).toEqual(before);
 });
 it('preserves zero, NA, substitutions and truncated summaries independently',()=>{
  const snapshot=coverageSnapshot();const usage=snapshot.result.extra!.knownUsage as {sourceUsage:Record<string,unknown>[]};const base=usage.sourceUsage[0];
  usage.sourceUsage=[{...base,knownValue:0,knownValueType:'number',knownQuality:'cleaned',coveredSeconds:3600,intervalCount:1000,detailsTruncated:true}, {...base,from:'2026-10-25T01:00:00+08:00',to:'2026-10-25T02:00:00+08:00',knownValueType:'na',knownQuality:'na'}, {...base,from:'2026-10-25T02:00:00+08:00',to:'2026-10-25T03:00:00+08:00',knownValue:5,knownValueType:'number',knownQuality:'substituted',coveredSeconds:3600,intervalCount:1}];
  const group=coverageGroups(snapshot)[0];expect(group.periods.map(p=>p.status)).toEqual(['complete','na','substituted']);expect(group.periods[0].value).toBe(0);expect(group.periods[1].value).toBeNull();expect(group.intervalCount).toBe(1001);expect(group.intervals).toHaveLength(0);expect(group.coveredSeconds).toBe(7200);expect(group.detailsTruncated).toBe(true);
 });
 it('keeps source units separate and avoids totals when diagnostic windows overlap',()=>{
  const snapshot=coverageSnapshot();const usage=snapshot.result.extra!.knownUsage as {sourceUsage:Record<string,unknown>[]};const base=usage.sourceUsage[0];
  usage.sourceUsage=[{...base,knownValue:10,knownQuality:'cleaned',coveredSeconds:3600,intervalCount:1},{...base,from:'2026-10-25T00:30:00+08:00',to:'2026-10-25T01:30:00+08:00',knownValue:20,knownQuality:'cleaned',coveredSeconds:3600,intervalCount:1},{...base,unit:'MWh',knownValue:2,knownQuality:'cleaned',coveredSeconds:3600,intervalCount:1}];
  const groups=coverageGroups(snapshot);expect(groups).toHaveLength(2);expect(groups[0].overlapping).toBe(true);expect(groups[0].coveredSeconds).toBeNull();expect(groups[0].intervalCount).toBeNull();expect(groups[1].coveredSeconds).toBe(3600);
 });
 it('merges numeric periods and retains the supplied raw detail rather than inventing missing rows',()=>{
  const snapshot=coverageSnapshot();const usage=snapshot.result.extra!.knownUsage as {sourceUsage:Record<string,unknown>[]};const base=usage.sourceUsage[0];const row={...base,knownValue:10,knownValueType:'number',knownQuality:'cleaned',coveredSeconds:3600,intervalCount:1,intervals:[{intervalStart:base.from,intervalEnd:base.to,value:10,valueType:'number',quality:'cleaned'}]};
  usage.sourceUsage=[row,{...row,from:'2026-10-25T01:00:00+08:00',to:'2026-10-25T02:00:00+08:00',intervals:[],detailsTruncated:true},row];
  const group=coverageGroups(snapshot)[0];expect(group.periods).toHaveLength(1);expect(group.periods[0].value).toBe(20);expect(group.periods[0].intervalCount).toBe(2);expect(group.intervals).toHaveLength(1);expect(group.coveredSeconds).toBe(7200);
 });
 it('replaces the raw diagnostic object with a bounded summary and on-demand detail',()=>{
  const snapshot=coverageSnapshot(),before=structuredClone(snapshot);
  const html=renderToStaticMarkup(createElement(ReportView,{snapshot}));
  expect(html).toContain('用量覆盖');
  expect(html).not.toContain('&quot;源点用量覆盖&quot;');
  expect(html).toContain('查看连续时段');
  expect(snapshot).toEqual(before);
 });
});
