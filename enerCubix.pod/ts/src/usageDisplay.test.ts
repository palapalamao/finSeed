import {it,expect} from 'vitest';
import {makeSnapshot} from './exports';
import type {ReportKind,ReportRequest,ReportResult} from './types';
const request=(kind:ReportKind):ReportRequest=>({kind,nodeIds:['m'],from:'2026-10-20T00:00:00+08:00',to:'2026-10-20T02:30:00+08:00',metric:'energy',period:'hour',perArea:false});
for(const kind of ['profile','ranking','proportion','utility','daily','comparison','primary','workingHours','workingDays','dashboard'] as const)it(`freezes one known quantity throughout ${kind}`,()=>{
 const q=request(kind),r:ReportResult={kind,from:q.from,to:q.to,period:'hour',asOf:'2026-10-20T02:10:00+08:00',series:[{id:'m|e',nodeId:'m',name:'Original meter',unit:'kWh',points:[{ts:q.from,value:null,quality:'missing',sourceIds:['p'],knownValue:30,knownValueType:'number',knownQuality:'filtered'}]}],rows:[{nodeId:'m',value:null,quality:'missing',knownValue:30,knownQuality:'filtered',percentage:null,knownPercentage:100}],summary:{totals:[{id:'m|e',value:null,quality:'missing'}],knownTotals:[{id:'m|e',value:30,valueType:'number',quality:'filtered'}]},extra:{usageBasis:'knownUsage',grandTotals:[{value:null,knownValue:30,knownQuality:'filtered'}],comparisons:[{current:null,reference:null,knownCurrent:30,knownReference:15,difference:null,percentage:null}]},warnings:[]};
 const s=makeSnapshot(q,r,'Test','test');
 expect(s.result.series[0].points[0]).toMatchObject({value:30,quality:'filtered',completeValue:null});
 expect(s.result.rows[0]).toMatchObject({value:30,percentage:100,completeValue:null,completePercentage:null});
 expect((s.result.summary.totals as Record<string,unknown>[])[0]).toMatchObject({value:30,completeValue:null});
 expect((s.result.extra?.grandTotals as Record<string,unknown>[])[0].value).toBe(30);
 expect((s.result.extra?.comparisons as Record<string,unknown>[])[0]).toMatchObject({current:30,reference:15,difference:null,percentage:null});
 expect(s.request.asOf).toBe(r.asOf);
 r.series[0].points[0].knownValue=999;expect(s.result.series[0].points[0].value).toBe(30);expect(r.rows[0].value).toBeNull();
});
