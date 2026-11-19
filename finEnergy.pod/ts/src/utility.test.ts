import {describe,expect,it} from 'vitest';
import {makeSnapshot} from './exports';
import {readableReportValue} from './reportDisplay';
import {utilityChartOptions,utilityGroups} from './utility';
import type {ReportSnapshot} from './types';

function snapshot():ReportSnapshot{
 const from='2026-10-01T00:00:00+08:00',to='2026-10-02T00:00:00+08:00';
 return {title:'End uses',project:'testproject',generatedAt:from,request:{kind:'utility',dimension:'metering',nodeIds:['a','b'],from,to,period:'day',metric:'energy',perArea:false},result:{kind:'utility',from,to,period:'day',series:[],rows:[],warnings:[],summary:{},extra:{utilityShares:[{utilityId:'lighting',name:'Lighting',categoryId:'e',unit:'kWh',value:300,percentage:50,percentageBasis:'knownUsage'},{utilityId:'power',name:'Power',categoryId:'e',unit:'kWh',value:300,percentage:50,percentageBasis:'knownUsage'}],utilityMembers:[{nodeId:'a',name:'A',utilityId:'lighting',categoryId:'e',unit:'kWh',value:300,quality:'filtered',coverage:.5,complete:false}]}}};
}
describe('end-use chart and export contract',()=>{
 it('uses amounts for geometry and the server share for labels, without re-summing percentages',()=>{
  const s=snapshot(),before=structuredClone(s),group=utilityGroups(s)[0];
  expect(group.total).toBe(600);expect(group.partial).toBe(true);
  const series=utilityChartOptions(group).series as {data:{value:number;percentage:number}[]}[];
  expect(series).toHaveLength(1);expect(series[0].data.map(d=>d.value)).toEqual([300,300]);expect(series[0].data.map(d=>d.percentage)).toEqual([50,50]);expect(s).toEqual(before);
 });
 it.each(['overlappingScopes','negativeConsumption','zeroKnownTotal','noKnownUsage'])('suppresses unsupported %s geometry',reason=>{
  const s=snapshot();(s.result.extra!.utilityShares as Record<string,unknown>[]).forEach(row=>{row.percentage=null;row.percentageBasis=reason;if(reason==='zeroKnownTotal')row.value=0;if(reason==='noKnownUsage')row.value=null;});
  const group=utilityGroups(s)[0];expect(group.reason).toBe(reason);expect((utilityChartOptions(group).series as {data:unknown[]}[])[0].data).toEqual([]);
 });
 it('separates energy types and units and disables normalized-intensity pies',()=>{
  const s=snapshot();(s.result.extra!.utilityShares as Record<string,unknown>[]).push({utilityId:'water',categoryId:'w',unit:'m³',value:7,percentage:100});expect(utilityGroups(s)).toHaveLength(2);s.request.perArea=true;expect(utilityGroups(s).every(g=>g.reason==='areaNormalized')).toBe(true);
 });
 it('keeps an unassigned end use visible in the frozen export',()=>{
  const s=snapshot();s.result.extra!.utilityShares=[{utilityId:'',name:'',categoryId:'e',unit:'kWh',value:9,percentage:100}];
  const frozen=makeSnapshot(s.request,s.result,s.title,s.project,new Date(s.generatedAt));
  const all=JSON.stringify(readableReportValue(frozen,'',frozen.result.extra));expect(all).toMatch(/未指定分项|Unassigned end use/);
 });
});
