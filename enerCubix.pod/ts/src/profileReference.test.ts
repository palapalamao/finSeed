import {expect,it} from 'vitest';
import {chartOptions} from './chartOptions';
import {profileGroups} from './reportDisplay';
import type {ReportSnapshot,Series} from './types';

const first='2026-10-01T00:00:00+08:00',second='2026-10-02T00:00:00+08:00';
function line(id:string,unit:string,values:(number|null)[]):Series{return {id,nodeId:id.split('|')[0],name:id,unit,points:values.map((value,index)=>({ts:index?second:first,value,quality:value===null?'missing':'ok',sourceIds:[id]}))};}
function snapshot():ReportSnapshot{return {title:'Profile',project:'test',generatedAt:second,request:{kind:'profile',nodeIds:['meter'],referenceIds:['temperature'],from:first,to:'2026-10-03T00:00:00+08:00',period:'day',metric:'energy',perArea:false},result:{kind:'profile',from:first,to:'2026-10-03T00:00:00+08:00',period:'day',rows:[],summary:{totals:[{id:'meter',value:120}]},warnings:[],series:[line('meter','kWh',[120,0]),line('temperature|reference','°C',[22,null])]}};}

it('adds reference curves to every compatible consumption chart without a separate reference panel',()=>{
 const s=snapshot();s.result.series.push({...line('water','m³',[5,6]),categoryId:'water'});
 const before=structuredClone(s);const groups=profileGroups(s);
 expect(groups).toHaveLength(2);
 expect(groups.map(group=>group.series.map(series=>series.id))).toEqual([['meter','temperature|reference'],['water','temperature|reference']]);
 expect(groups.every(group=>!group.title.includes('参考曲线'))).toBe(true);
 expect(s).toEqual(before);
});

it('keeps energy bars on the left and reference lines on an independent right axis',()=>{
 const s=snapshot(),before=structuredClone(s);
 const option=chartOptions(s.result,{}, {request:s.request});
 expect(option.yAxis).toMatchObject([{name:'kWh',position:'left',scale:false},{name:'°C',position:'right',scale:true}]);
 expect(option.series).toMatchObject([{type:'bar',yAxisIndex:0,data:[{value:120},{value:0}]},{type:'line',yAxisIndex:1,connectNulls:false,data:[{value:22},{value:null}]}]);
 expect(s).toEqual(before);
});

it('recognizes request-selected reference points even without the legacy ID suffix',()=>{
 const s=snapshot();s.result.series[1].id='temperature';
 const option=chartOptions(s.result,{}, {request:s.request});
 expect(profileGroups(s)).toHaveLength(1);
 expect(option.series).toMatchObject([{type:'bar'},{type:'line',yAxisIndex:1}]);
});

it('shares reference axes by unit while keeping equal-unit consumption and reference values separate',()=>{
 const s=snapshot();s.result.series.push(line('humidity|reference','%',[60,65]),line('secondTemperature|reference','°C',[20,21]),line('counter|reference','kWh',[1000,1100]));
 const option=chartOptions(s.result,{}, {request:s.request});
 expect(option.yAxis).toMatchObject([{name:'kWh',position:'left'},{name:'°C',position:'right'},{name:'%',position:'right'},{name:'kWh',position:'right'}]);
 expect((option.series as {yAxisIndex:number}[]).map(series=>series.yAxisIndex)).toEqual([0,1,2,1,3]);
});

it('leaves reference curves as lines when the consumption chart switches to line mode',()=>{
 const s=snapshot();const option=chartOptions(s.result,{}, {type:'line',request:s.request});
 expect(option.series).toMatchObject([{type:'line',yAxisIndex:0},{type:'line',yAxisIndex:1}]);
});
