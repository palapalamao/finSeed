import {expect,it} from 'vitest';
import {chartOptions} from './chartOptions';
import {leakGroups,profileGroups} from './reportDisplay';
import {comparisonChartOptions} from './comparison';
import {filterSnapshot} from './exports';
import type {ReportKind,ReportSnapshot,Series} from './types';

const from='2026-10-02T00:00:00+08:00',previous='2026-10-01T00:00:00+08:00';
const meter:Series={id:'m|e',nodeId:'m',name:'Main',categoryId:'e',unit:'kWh',points:[{ts:from,value:50,quality:'ok',sourceIds:['mp']}]};
const reference:Series={id:'temp|reference',nodeId:'weather',name:'Outside temperature',role:'reference',referencePeriod:'current',unit:'°C',points:[{ts:from,value:0,quality:'partial',sourceIds:['temp'],validSamples:1,expectedSamples:2,naSamples:1,missingSamples:0}]};
function snapshot(kind:ReportKind):ReportSnapshot{return {title:kind,project:'test',generatedAt:from,request:{kind,nodeIds:['m'],referenceIds:['temp'],from,to:'2026-10-03T00:00:00+08:00',period:'day',metric:'energy',perArea:false},result:{kind,from,to:'2026-10-03T00:00:00+08:00',period:'day',series:[structuredClone(meter),structuredClone(reference)],summary:{totals:[{id:meter.id,value:50}]},warnings:[],rows:[{nodeId:'m',categoryId:'e',unit:'kWh',ts:from,total:50,submeter:40},{nodeId:'weather',role:'reference',ts:from,value:0,unit:'°C'}]}};}

it.each(['daily','utility','primary'] as const)('%s overlays references on the original bars and right axis',kind=>{
 const s=snapshot(kind),option=chartOptions(s.result,{}, {request:s.request,dailyColorBy:'band'});
 expect(option.series).toMatchObject([{type:'bar',yAxisIndex:0},{type:'line',yAxisIndex:1,connectNulls:false,data:[{value:0}]}]);
 expect(option.yAxis).toMatchObject([{name:'kWh',position:'left'},{name:'°C',position:'right'}]);
 const temp=(option.series as {data:Record<string,unknown>[]}[])[1];expect(temp.data[0].itemStyle).toBeUndefined();
});
it('primary groups include reference curves without a separate reference chart',()=>{
 const s=snapshot('primary');expect(profileGroups(s)).toHaveLength(1);expect(profileGroups(s)[0].series.map(line=>line.id)).toEqual([meter.id,reference.id]);
});
it('leak overlays reference lines without adding reference objects or rows to meter stacks',()=>{
 const s=snapshot('leak');s.result.extra={leakBranches:[{nodeId:'m',categoryId:'e',unit:'kWh',branchId:'child',name:'Child',ts:from,value:40}]};
 const groups=leakGroups(s);expect(groups).toHaveLength(1);expect(groups[0].result.series).toHaveLength(2);
 const option=chartOptions(groups[0].result);
 expect(option.xAxis).toMatchObject({data:[from]});
 expect(option.series).toMatchObject([{type:'bar',data:[{value:50}]},{type:'bar',stack:'submeters',data:[{value:40}]},{type:'line',yAxisIndex:1,data:[{value:0}]}]);
});
it('comparison keeps energy pairs and matches each reference to its real period',()=>{
 const s=snapshot('comparison');s.request.otherFrom=previous;s.request.otherTo=from;s.request.comparisonAlignment='duration';
 s.result.series.splice(1,0,{...structuredClone(meter),id:meter.id+'|reference',points:[{ts:previous,value:40,quality:'ok',sourceIds:['mp']}]});
 s.result.series.push({...structuredClone(reference),id:reference.id+'|comparison',referencePeriod:'comparison',points:[{ts:previous,value:15,quality:'ok',sourceIds:['temp']}]});
 const option=comparisonChartOptions(s.result,s.request),lines=option.series as {name:string;type:string;data:{ts:string;value:number}[];lineStyle?:{type:string}}[];
 expect(lines.map(line=>line.type)).toEqual(['bar','bar','line','line']);
 expect(lines[2].name).toContain('本期');expect(lines[3].name).toContain('对比期');expect(lines[3].lineStyle?.type).toBe('dashed');
 expect(lines.map(line=>line.data[0].value)).toEqual([50,40,0,15]);expect(lines[3].data[0].ts).toBe(previous);
});
it('category filtering retains frozen reference observations and coverage without changing meter totals',()=>{
 const s=snapshot('profile');s.result.extra={referenceCurves:[{pointId:'temp',validSamples:1,expectedSamples:2}]};const before=structuredClone(s);
 const filtered=filterSnapshot(s,['e'],['Electricity'])!;
 expect(filtered.result.series.map(line=>line.id)).toEqual([meter.id,reference.id]);
 expect(filtered.result.rows.some(row=>row.role==='reference')).toBe(true);
 expect(filtered.result.extra?.referenceCurves).toEqual(s.result.extra.referenceCurves);
 expect(filtered.result.summary).toEqual(s.result.summary);expect(s).toEqual(before);
});
