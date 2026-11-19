import {describe,expect,it} from 'vitest';
import {cleaningChartData,cleaningChartOption,cleaningZoomRange} from './cleaningChart';
import type {CleaningPreview} from './cleaning';

const start='2026-10-24T00:00:00+08:00',end='2026-10-24T00:00:10+08:00';
const preview:CleaningPreview={raw:[{ts:start,value:100},{ts:end,value:90}],cleaned:[{ts:start,value:null,valueType:'na'},{ts:end,value:0}],details:[{ts:start,intervalStart:start,intervalEnd:end,rawValue:90,reason:'deltaMin',value:null,valueType:'na',emitted:true}],summary:{},profileSnapshot:{}};
describe('cleaning preview chart',()=>{
 it('preserves acquisition and interval-start timestamps without another difference',()=>{
  const before=JSON.stringify(preview),data=cleaningChartData(preview);
  expect(data.raw.map(row=>row.value)).toEqual([[Date.parse(start),100],[Date.parse(end),90]]);
  expect(data.cleaned.map(row=>row.value)).toEqual([[Date.parse(start),null],[Date.parse(end),0]]);
  expect(data.cleaned[0].reading.valueType).toBe('na');expect(JSON.stringify(preview)).toBe(before);
 });
 it('marks an anomaly over its real interval and at the raw acquisition endpoint',()=>{
  const data=cleaningChartData(preview),anomaly=data.anomalies[0];
  expect(anomaly).toMatchObject({start:Date.parse(start),end:Date.parse(end),rawValue:90,reason:'deltaMin'});
  const option=cleaningChartOption(data,'kWh');
  expect(option.grid).toHaveLength(2);expect(option.xAxis).toHaveLength(2);
  expect(option.dataZoom).toEqual(expect.arrayContaining([expect.objectContaining({type:'inside',filterMode:'filter'}),expect.objectContaining({type:'slider',filterMode:'filter'})]));
  expect(option.series).toEqual(expect.arrayContaining([expect.objectContaining({type:'line',connectNulls:false,yAxisIndex:0}),expect.objectContaining({type:'bar',yAxisIndex:1})]));
  expect(option.series).toEqual(expect.arrayContaining([expect.objectContaining({type:'scatter',data:[expect.objectContaining({value:[Date.parse(end),90]})]})]));
 });
 it('reserves space for long axis labels and uses a zero-based consumption axis',()=>{
  const option=cleaningChartOption(cleaningChartData(preview),'kWh');
  expect(option.grid).toEqual([expect.objectContaining({outerBoundsMode:'same'}),expect.objectContaining({outerBoundsMode:'same'})]);
  expect(option.yAxis).toEqual([expect.objectContaining({scale:true,axisLine:{show:true,lineStyle:expect.anything()},axisTick:{show:true}}),expect.objectContaining({scale:false,axisLine:{show:true,lineStyle:expect.anything()},axisTick:{show:true}})]);
  const series=option.series as {type:string;data:{value:[number,number|null]}[]}[];
  expect(series[1].data.map(row=>row.value)).toEqual([[Date.parse(start),null],[Date.parse(end),0]]);
 });
 it('keeps missing/NA as gaps and never manufactures an anomaly reading at zero',()=>{
  const data=cleaningChartData({...preview,raw:[{ts:start,value:null,valueType:'na'},{ts:end,value:null,valueType:'null'}],details:[{...preview.details[0],rawValue:'NA',reason:'inputNA'}]});
  expect(data.raw.map(row=>row.value[1])).toEqual([null,null]);
  const series=cleaningChartOption(data,'kWh').series as {type:string;data:unknown[]}[];
  expect(series.find(row=>row.type==='scatter')?.data).toEqual([]);
  expect(data.anomalies).toHaveLength(1);
 });
 it('ignores baseline diagnostics and clips anomaly navigation to the query range',()=>{
  const data=cleaningChartData({...preview,from:start,to:'2026-10-25T00:00:00+08:00',details:[{reason:'noPrevious',ts:start},...preview.details,{reason:'ok',intervalStart:start,intervalEnd:end}]});
  expect(data.anomalies).toHaveLength(1);
  const zoom=cleaningZoomRange(data,0)!;expect(zoom.startValue).toBe(Date.parse(start));expect(zoom.endValue).toBeLessThan(data.max);
  expect(zoom.endValue-zoom.startValue).toBeGreaterThanOrEqual(60000);
  expect(cleaningZoomRange(data,1)).toBeUndefined();
 });
 it('handles empty results and corrected rollover intervals',()=>{
  expect(cleaningChartData({...preview,raw:[],cleaned:[],details:[]}).hasValues).toBe(false);
  expect(cleaningChartData({...preview,details:[{...preview.details[0],reason:'rollover'}]}).anomalies[0].corrected).toBe(true);
 });
 it('keeps simultaneous source events distinct without plotting source readings on the total curve',()=>{
  const data=cleaningChartData({...preview,pointId:'total',details:['a','b'].map(pointId=>({...preview.details[0],pointId,reason:'rollover',rawValue:12}))});
  expect(data.anomalies.map(row=>row.detail.pointId)).toEqual(['a','b']);
  const series=cleaningChartOption(data,'kWh').series as {type:string;data:unknown[]}[];
  expect(series.find(row=>row.type==='scatter')?.data).toEqual([]);
 });
});
