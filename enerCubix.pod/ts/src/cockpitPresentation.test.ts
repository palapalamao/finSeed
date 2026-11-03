import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {CockpitIssues} from './CockpitIssues';
import budgetRaw from '../tests/fixtures/cockpit-budget-24day.json';
import {afterEach,expect,it,vi} from 'vitest';
import raw from '../tests/fixtures/cockpit-faces-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import type {Catalog} from './types';
import {freezeCockpitExport,cockpitExportTables,cockpitPrintEvidence} from './cockpitExports';
afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});
for(const language of ['zh-CN','en-US'] as const)it('uses the frozen budget state in the business brief '+language,async()=>{
 const {initializeLocale,t}=await import('./i18n'),{CockpitBrief}=await import('./CockpitBrief');initializeLocale(language);
 const snapshot=structuredClone(budgetRaw) as unknown as CockpitSnapshot,b=snapshot.modules.kpis!.data!.budget!,before=structuredClone(snapshot);
 const catalog:Catalog={version:'test',project:snapshot.context.project,user:{name:'test',canWrite:false},records:[]};
 const render=()=>renderToStaticMarkup(createElement(CockpitBrief,{snapshot,catalog,onProfile:()=>{},onFlow:()=>{}}));
 const absent=language==='zh-CN'?'未配置预算，不作预算达标判断。':'No budget is configured; budget compliance is not assessed.';
 const complete=render();expect(complete).toContain('240,000');expect(complete).toContain('224,600');expect(complete).not.toContain(absent);expect(snapshot).toEqual(before);
 Object.assign(b,{status:'unavailable',budgetStatus:'ok',comparisonStatus:'unavailable',variancePct:null,monthUsagePct:null,referenceVariancePct:9.74,referenceMonthUsagePct:10.45,costQuality:'partial',costValueBasis:'knownSubtotal',reasonCodes:['BUDGET_COST_INCOMPLETE']});
 const reference=render();expect(reference).toContain(language==='zh-CN'?'参考偏差':'Reference variance');expect(reference).toContain('9.74');expect(reference).toContain(t('已有费用含不完整或估算数据；比例仅供参考，不作达标判断。'));expect(reference).not.toContain(absent);
 delete snapshot.modules.kpis!.data!.budget;
 const missing=render();expect(missing).toContain(language==='zh-CN'?'预算':'budget');expect(missing).not.toContain('240,000');expect(missing).not.toContain('9.74');
});
it('freezes complete snapshot, language and native names without rounding0/NA/null',()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 snapshot.context.comparison={mode:'previousMonth',from:'2026-09-01T00:00:00Z',to:'2026-09-03T02:00:00Z'};
 const packet=freezeCockpitExport(snapshot,'en-US',{a:'设备A原名'});snapshot.boundary.meterIds.length=0;snapshot.context.comparison.mode='none';snapshot.context.comparison.from='2030-01-01T00:00:00Z';
 expect(packet.snapshot.boundary.meterIds).toEqual(['a','b']);expect(packet.language).toBe('en-US');expect(packet.objects.a).toBe('设备A原名');
 expect(packet.snapshot.context.comparison).toEqual({mode:'previousMonth',from:'2026-09-01T00:00:00Z',to:'2026-09-03T02:00:00Z'});
 const reports=cockpitExportTables(packet);expect(reports.some(table=>table.id==='face-daily')).toBe(true);expect(reports.some(table=>table.id==='face-endUse')).toBe(true);expect(reports.flatMap(table=>table.rows).some(row=>row.includes(120))).toBe(true);
});
it('switches per-user language in place and refreshes shared report and quality labels',async()=>{
 const saved=new Map<string,string>();vi.stubGlobal('localStorage',{getItem:(k:string)=>saved.get(k)||null,setItem:(k:string,v:string)=>saved.set(k,v),removeItem:(k:string)=>saved.delete(k)});const reload=vi.fn();vi.stubGlobal('location',{reload});
 const i18n=await import('./i18n');i18n.initializeLocale('zh-CN','su');const {reportLabels}=await import('./reportDisplay'),{qualityLabel}=await import('./reportQuality');const listener=vi.fn();const off=i18n.subscribeLocale(listener);i18n.changeLanguage('en-US',{inPlace:true});expect(reload).not.toHaveBeenCalled();expect(listener).toHaveBeenCalledTimes(1);expect(i18n.locale).toBe('en-US');expect(reportLabels.sourceIds).toBe('Source points');expect(qualityLabel('missing')).not.toMatch(/历史/);i18n.changeLanguage('auto',{inPlace:true});expect(i18n.locale).toBe('zh-CN');expect(reportLabels.sourceIds).toBe('源点');off();
 i18n.initializeLocale('en-US','other');expect(i18n.locale).toBe('en-US');
});

it('restores a366-local-day interval across DST without accepting unbounded URLs',async()=>{
 const {createNavigation,encodeNavigation,decodeNavigation}=await import('./cockpitNavigation');const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;snapshot.context.time.from='2024-11-02T00:00:00-04:00';snapshot.context.time.to='2025-11-03T00:00:00-05:00';snapshot.context.asOf=snapshot.context.time.to;const n=createNavigation(snapshot,'profile',{selectedFace:'time',presentationMode:false,scrollY:0,draft:{scope:snapshot.context.reportScope,categoryId:'c',preset:'custom'}});expect(decodeNavigation(encodeNavigation(n),'test')).toBeTruthy();n.targetRequest.to='2027-11-03T00:00:00-05:00';expect(decodeNavigation(encodeNavigation(n),'test')).toBeUndefined();
});

it('deduplicates identical diagnostic blocks without dropping any report evidence',()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot,packet=freezeCockpitExport(snapshot,'zh-CN',{}),printed=cockpitPrintEvidence(packet);
 for(const [id,report]of Object.entries(snapshot.reports))for(const [key,value]of Object.entries(report.extra||{})){
  if(key==='knownUsage')continue;const projected=printed.reports[id].extra[key] as {evidenceRef?:string};expect(projected&&typeof projected==='object'&&projected.evidenceRef?printed.definitions[projected.evidenceRef]:projected).toEqual(value);
 }
});

it('renders providedNA and real0 distinctly in issue actual and hourly evidence',async()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 const item={id:'na-event',type:'energyAlarm' as const,objectId:'a',categoryId:'c',unit:'kWh',evidenceFrom:null,evidenceTo:null,active:true,acknowledged:false,stateObservedAt:null,sourceIds:[],actual:null as number|null,valueType:'na' as 'na'|'number',hours:[{ts:'2026-10-01T00:00:00Z',value:null as number|null,limit:10,quality:'na',unit:'kWh'}]};snapshot.modules.issues={status:'ok',data:{stateObservedAt:null,items:[item],total:1,topIds:['na-event'],activeEventCount:1,eventScope:{basis:'selectedObjectsAndEffectiveMeters',objectIds:['a'],meterIds:['a'],categoryId:'c'}}};
 const render=()=>renderToStaticMarkup(createElement(CockpitIssues,{snapshot,name:(id:string)=>id,canEvidence:()=>false,onEvidence:()=>{}}));expect(render()).toContain('<dd>NA kWh</dd>');expect(render()).toContain('<td>NA</td>');item.actual=0;item.valueType='number';item.hours[0].value=0;item.hours[0].quality='ok';expect(render()).toContain('<dd>0 kWh</dd>');expect(render()).toContain('<td>0</td>');
});

it('prints explicit raw-interval dataset counts while full snapshot keeps every diagnostic',()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;const report=Object.values(snapshot.reports)[0];report.extra={diagnostic:{intervalCount:120,detailsTruncated:true,truncationReason:'sourceLimit',intervals:Array.from({length:100},(_,index)=>({index,value:index}))}};const packet=freezeCockpitExport(snapshot,'en-US',{}),printed=cockpitPrintEvidence(packet),diagnostic=Object.values(printed.definitions).find((v:any)=>v?.intervalCount===120) as any;
 expect(diagnostic.intervals).toMatchObject({datasetRef:expect.any(String),returnedCount:100,totalCount:120,truncated:true,reason:'sourceLimit'});expect((packet.snapshot.reports[Object.keys(packet.snapshot.reports)[0]].extra!.diagnostic as any).intervals).toHaveLength(100);
});

it('reformats retained resource and network failures after language changes without requerying',async()=>{
 const i18n=await import('./i18n'),{CockpitQuery,cockpitQueryError}=await import('./cockpitQuery'),{absoluteCockpitRequest}=await import('./cockpitNavigation');const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 for(const initial of ['zh-CN','en-US'])for(const kind of ['resource','network','business']){
  i18n.initializeLocale(initial);let calls=0;const query=new CockpitQuery(async()=>{calls++;if(kind==='resource')throw Object.assign(new Error(i18n.serverMessage('cockpitBusy')),{code:'COCKPIT_BUSY',sourceMessage:'cockpitBusy'});if(kind==='network')throw Object.assign(new Error(i18n.t('无法连接 FIN，请检查网络与当前会话。')),{code:'network'});throw new Error('设备A原名：现场信息');});query.restore(snapshot);await query.apply(absoluteCockpitRequest(snapshot));i18n.initializeLocale(initial==='zh-CN'?'en-US':'zh-CN');const message=cockpitQueryError(query.getSnapshot());expect(calls).toBe(1);expect(query.getSnapshot().snapshot?.snapshotId).toBe(snapshot.snapshotId);if(kind==='business')expect(message).toBe('设备A原名：现场信息');else expect(message).toBe(i18n.serverMessage(kind==='resource'?'cockpitBusy':'无法连接 FIN，请检查网络与当前会话。'));
 }
});

it('updates professional report group labels in the same application session',async()=>{
 vi.stubGlobal('localStorage',{getItem:()=>null,setItem:()=>{},removeItem:()=>{}});const i18n=await import('./i18n');i18n.initializeLocale('zh-CN','su');const {analysisGroup}=await import('./navigation');expect(analysisGroup('profile')!.label).toBe('趋势与负荷');i18n.changeLanguage('en-US',{inPlace:true});expect(analysisGroup('profile')!.label).toBe('Trends and load');
});
