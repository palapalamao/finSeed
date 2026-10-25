import {describe,it,expect} from 'vitest';
import dayjs from 'dayjs';
import {comparisonPreset,alignComparison,comparisonSlots,comparisonChartOptions,comparisonTemplateObjects} from './comparison';
import type {ReportRequest,ReportResult} from './types';

describe('aligned comparison periods',()=>{
 it('defaults October 22 to October 1–22 against September 1–22, inclusive',()=>{
  const value=comparisonPreset('monthToDate',dayjs('2026-10-22T14:00:00'));
  expect([...value.range,...value.otherRange].map(date=>date.format('YYYY-MM-DD'))).toEqual(['2026-10-01','2026-10-23','2026-09-01','2026-09-23']);
 });
 it('limits both month-to-date periods to the shorter month, including leap years',()=>{
  for(const [date,end]of [['2024-03-31','2024-03-30'],['2026-03-31','2026-03-29']]){
   const value=comparisonPreset('monthToDate',dayjs(date));expect(value.range[1].format('YYYY-MM-DD')).toBe(end);
   expect(value.range[1].diff(value.range[0],'day')).toBe(value.otherRange[1].diff(value.otherRange[0],'day'));
  }
 });
 it('links the second end date to seven days and supports year boundaries',()=>{
  const value=alignComparison([dayjs('2026-01-01'),dayjs('2026-01-08')],dayjs('2025-12-25'));
  expect(value.otherRange[1].format('YYYY-MM-DD')).toBe('2026-01-01');
  expect(value.preset).toBe('custom');
 });
 it('keeps full calendar months instead of discarding the 31st day',()=>{
  const value=comparisonPreset('months',dayjs('2026-10-22'));
  expect(value.alignment).toBe('calendarMonth');
  expect(value.range[1].diff(value.range[0],'day')).toBe(31);expect(value.otherRange[1].diff(value.otherRange[0],'day')).toBe(30);
 });
 it('anchors weeks at each range start instead of weekday-dependent calendar weeks',()=>{
  expect(comparisonSlots('2026-10-01T00:00:00+08:00','2026-10-08T00:00:00+08:00','week','duration')).toHaveLength(1);
 });
});

describe('paired comparison bars',()=>{
 const request:ReportRequest={kind:'comparison',nodeIds:['m'],from:'2026-10-01T00:00:00+08:00',to:'2026-10-04T00:00:00+08:00',otherFrom:'2026-09-01T00:00:00+08:00',otherTo:'2026-09-04T00:00:00+08:00',comparisonAlignment:'duration',period:'day',metric:'energy',perArea:false};
 const point=(ts:string,value:number|null)=>({ts,value,quality:value===null?'missing':'ok',sourceIds:['p']});
 const result:ReportResult={kind:'comparison',from:request.from,to:request.to,period:'day',warnings:[],rows:[],summary:{},series:[{id:'m|c',name:'水表',unit:'m³',points:[point(request.from,10),point('2026-10-03T00:00:00+08:00',30)]},{id:'m|c|reference',name:'水表 (reference)',unit:'m³',points:[point(request.otherFrom!,8),point('2026-09-02T00:00:00+08:00',null),point('2026-09-03T00:00:00+08:00',0)]}]};
 it('pairs the actual dates, leaves missing slots blank, and preserves zero',()=>{
  const original=structuredClone(result);const option=comparisonChartOptions(result,request) as any;
  expect(option.series.map((series:any)=>series.type)).toEqual(['bar','bar']);expect(option.xAxis.data).toHaveLength(3);
  expect(option.series[0].data.map((point:any)=>point.value)).toEqual([10,null,30]);expect(option.series[1].data.map((point:any)=>point.value)).toEqual([8,null,0]);
  expect(option.series[1].data[2].ts).toBe('2026-09-03T00:00:00+08:00');expect(result).toEqual(original);
 });
 it('groups different objects in the same period without shifting dates',()=>{
  const {otherFrom,otherTo,...nodes}=request;const option=comparisonChartOptions({...result,series:[result.series[0]]},nodes) as any;
  expect(option.series[0].type).toBe('bar');expect(option.xAxis.data).toHaveLength(3);
 });
 it('labels the explicitly selected object as the baseline',()=>{
  const {otherFrom,otherTo,...nodes}=request;const option=comparisonChartOptions({...result,series:[result.series[0]]},{...nodes,baselineId:'m'}) as any;
  expect(option.series[0].name).toContain('基准');
 });
});
it('merges legacy objects but preserves raw point semantics even when a meter archive exists',()=>{
 const saved={nodeIds:['m1'],referenceIds:['m2','p1','raw']} as ReportRequest;
 const value=comparisonTemplateObjects(saved,[{id:'m1',kind:'meter',name:'A',pointId:'p1'},{id:'m2',kind:'meter',name:'B',pointId:'p2'},{id:'raw',kind:'nativePoint',name:'FIN 原点'}]);
 expect(value).toEqual({nodeIds:['m1','m2'],referenceIds:['p1','raw']});expect(saved.referenceIds).toEqual(['m2','p1','raw']);
});
