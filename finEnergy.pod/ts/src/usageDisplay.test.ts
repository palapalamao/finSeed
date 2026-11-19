import {it,expect} from 'vitest';
import {makeSnapshot,reportTables} from './exports';
import {readableReportValue} from './reportDisplay';
import {t} from './i18n';
import type {ReportKind,ReportRequest,ReportResult} from './types';
it('exports available master and participation totals without replacing an incomplete leakage difference or query bounds',()=>{
 const q=request('leak'),r:ReportResult={kind:'leak',from:q.from,to:q.to,period:'hour',asOf:q.from,series:[],warnings:[],summary:{},rows:[{nodeId:'m',ts:q.from,knownTotal:100,knownSubmeter:40,difference:null,percentage:null,membershipQuality:'topologyUnknown'}],extra:{leakOwnUsage:[{nodeId:'m',name:'Original meter',value:100,unit:'kWh'}]}};
 const before=structuredClone(r),snapshot=makeSnapshot(q,r,'Balance','test'),table=reportTables(snapshot);
 expect(snapshot.result.rows[0]).toMatchObject({knownTotal:100,knownSubmeter:40,difference:null,percentage:null});expect(snapshot.result.from).toBe(q.from);expect(snapshot.result.to).toBe(q.to);expect(table.rows[0]).toContain('100');expect(table.rows[0]).toContain('40');expect(r).toEqual(before);
});
const request=(kind:ReportKind):ReportRequest=>({kind,nodeIds:['m'],from:'2026-10-20T00:00:00+08:00',to:'2026-10-20T02:30:00+08:00',metric:'energy',period:'hour',perArea:false});
it.each([
 [924821,974613,-49792,-49792/924821*100],
 [100,40,60,60],
 [0,40,-40,null],
 [0,0,0,null],
 [null,40,null,null],
 [100,null,null,null],
])('retains a signed available-use comparison for %s minus %s without inventing a complete balance',(master,branches,difference,percentage)=>{
 const q=request('leak'),total={nodeId:'m',categoryId:'e',unit:'kWh',knownTotal:master,knownSubmeter:branches,difference:null,percentage:null};
 const r:ReportResult={kind:'leak',from:q.from,to:q.to,period:'hour',series:[],rows:[],warnings:[],summary:{},extra:{relationBasis:'current',leakTotals:[total]}};
 const before=structuredClone(r),snapshot=makeSnapshot(q,r,'Balance','test');
 expect((snapshot.result.extra?.leakTotals as Record<string,unknown>[])[0]).toMatchObject({availableDifference:difference,availableDifferencePercentage:percentage,difference:null,percentage:null});
 const exported=JSON.stringify(readableReportValue(snapshot,'',snapshot.result.extra));
 expect(exported).toContain(t('已有用量差值（总表 − 分表）'));expect(exported).toContain(t('已有用量差值比例 (%)'));
 expect(r).toEqual(before);
});
it('preserves legacy complete-balance summaries without available-use fields',()=>{
 const q=request('leak'),total={nodeId:'m',total:100,submeter:40,difference:60,percentage:60};
 const r:ReportResult={kind:'leak',from:q.from,to:q.to,period:'hour',series:[],rows:[],warnings:[],summary:{},extra:{leakTotals:[total]}};
 expect(makeSnapshot(q,r,'Balance','test').result.extra?.leakTotals).toEqual([total]);
});
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
