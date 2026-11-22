import {describe,expect,it,vi} from 'vitest';
import {chartFirstRequest,profileChartStage,rebuildFullProfile} from './profileFirst';
import type {FinEnergyApi} from './api';
import type {ReportRequest,ReportResult,ReportSnapshot} from './types';

const request:ReportRequest={kind:'profile',dimension:'space',spaceSource:'fin',nodeIds:['s'],from:'2026-09-01T00:00:00Z',to:'2026-10-01T00:00:00Z',asOf:'2026-09-25T12:00:00Z',period:'day',metric:'energy',perArea:false};
const result=(value:number):ReportResult=>({kind:'profile',from:request.from,to:request.to,asOf:request.asOf,period:'day',warnings:[],rows:[],summary:{},series:[{id:'s|e',nodeId:'s',name:'Building',unit:'kWh',points:[{ts:request.from,value,quality:'ok',sourceIds:['pt']}]}]});
const chart=():ReportSnapshot=>({request:structuredClone(request),result:{...result(10),extra:{profileDelivery:{mode:'chart',diagnostics:'deferred',snapshotId:'chart-read-A'}}},title:'Profile',project:'test',generatedAt:'2026-11-22T01:00:00Z'});

describe('ordinary profile delivery contract',()=>{
 it('opts in only for the narrow space/day/energy shape without mutating templates',()=>{
  const before=structuredClone(request);expect(chartFirstRequest(request).responseMode).toBe('chart');expect(request).toEqual(before);
  for(const change of [{kind:'daily'},{period:'hour'},{metric:'cost'},{dimension:'organization'},{perArea:true},{referenceIds:['weather']},{otherFrom:request.from}] as Partial<ReportRequest>[]){const q={...request,...change};expect(chartFirstRequest(q)).toBe(q);}
 });
 it('replaces the complete snapshot when history has been backfilled despite an unchanged asOf',async()=>{
  const original=chart(),before=structuredClone(original),full={...result(20),warnings:['new warning'],extra:{cleaning:[{pointId:'pa'}],knownUsage:{sourceUsage:[{pointId:'pa'}]}}};
  const report=vi.fn(async()=>full),points=vi.fn(async()=>({items:[{id:'pt',name:'Main',his:true}],total:1,offset:0,limit:10})),controller=new AbortController();
  const rebuilt=await rebuildFullProfile(original,{report,points} as unknown as FinEnergyApi,[],controller.signal);
  expect(report).toHaveBeenCalledWith({...request,responseMode:'full'},controller.signal);
  expect(rebuilt.result.series[0].points[0].value).toBe(20);expect(rebuilt.result.warnings).toEqual(['new warning']);
  expect(rebuilt.result.extra?.profileDelivery).toBeUndefined();expect(rebuilt.replacesSnapshot?.generatedAt).toBe(original.generatedAt);
  expect(rebuilt.generatedAt).not.toBe(original.generatedAt);expect(rebuilt.request.asOf).toBe(original.request.asOf);expect(original).toEqual(before);
  expect(profileChartStage(rebuilt)).toBe(false);
 });
 it('refuses to treat another chart-stage response as a complete export',async()=>{
  const source=chart(),api={report:async()=>source.result,points:async()=>({items:[],total:0,offset:0,limit:10})} as unknown as FinEnergyApi;
  await expect(rebuildFullProfile(source,api,[],new AbortController().signal)).rejects.toThrow();
 });
 it('propagates full-read failure without modifying the displayed chart',async()=>{
  const source=chart(),before=structuredClone(source),api={report:async()=>{throw new Error('read failed');}} as unknown as FinEnergyApi;
  await expect(rebuildFullProfile(source,api,[],new AbortController().signal)).rejects.toThrow('read failed');expect(source).toEqual(before);
 });
});
