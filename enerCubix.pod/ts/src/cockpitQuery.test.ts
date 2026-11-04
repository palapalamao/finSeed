import {describe,expect,it,vi} from 'vitest';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));
import {ApiError} from './api';
import {CockpitQuery,defaultCockpitSelection,accessibleCockpitSiteIds} from './cockpitQuery';
import type {CockpitRequest,CockpitSnapshot} from './cockpitTypes';
import type {Catalog} from './types';
export const request=(id:string):CockpitRequest=>({schemaVersion:1,requestId:id,reportScope:{dimension:'space',nodeIds:['site'],selectionIntent:'range'},focusCategoryId:'electricity',time:{preset:'thisMonth',period:'day'},modules:['kpis','trend']});
export const snapshot=(id:string):CockpitSnapshot=>({schemaVersion:1,snapshotId:'snapshot-'+id,requestId:id,generatedAt:'2026-10-31T14:37:03+08:00',context:{project:'test',projectTimeZone:'Asia/Shanghai',reportScope:request(id).reportScope,focusCategoryId:'electricity',time:{preset:'thisMonth',period:'day',from:'2026-10-01T00:00:00+08:00',to:'2026-10-31T14:37:00+08:00'},asOf:'2026-10-31T14:37:00+08:00'},provenance:{configFingerprint:'config',relationshipBasis:'currentConfiguration',historyBasis:'ownPrimaryPointRaw',historyObservedFrom:'2026-10-31T14:37:00+08:00',historyObservedTo:'2026-10-31T14:37:02+08:00',sourceLastObservedAt:null,configRefs:[]},boundary:{id:'b',meterIds:['meter'],sourcePointIds:['primary'],aggregateAllowed:true,overlaps:[],excluded:[]},modules:{kpis:{status:'partial',data:{values:[{id:'energy',categoryId:'electricity',value:0,valueType:'number',unit:'kWh',quality:'partial',valueBasis:'knownSubtotal',completeValue:null,knownValue:0,sourceIds:['primary']}],conclusions:[]}}},reports:{},quality:[],capabilities:{canRead:true,canManage:false,availableFaces:[]},limitations:[]});
function deferred<T>(){let resolve!:(value:T)=>void,reject!:(reason:Error)=>void;const promise=new Promise<T>((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};}

it('uses only actual accessible site IDs for the all-sites draft while preserving the single-site default',()=>{
 const catalog:Catalog={project:'local',version:'test',user:{name:'reader',canWrite:false},records:[
  {id:'north',kind:'space',name:'North',nativeSourceKind:'site'},
  {id:'south',kind:'space',name:'South',nativeSourceKind:'site'},
  {id:'north',kind:'space',name:'Duplicate',nativeSourceKind:'site'},
  {id:'hidden',kind:'space',name:'Hidden',nativeSourceKind:'site',nativeHidden:true},
  {id:'floor',kind:'space',name:'Floor',parentId:'north',nativeSourceKind:'floor'},
  {id:'c',kind:'category',name:'Electricity',unit:'kWh'},
  {id:'m',kind:'meter',name:'M',categoryId:'c',pointId:'p'}
 ]};
 const before=structuredClone(catalog);expect(accessibleCockpitSiteIds(catalog)).toEqual(['north','south']);
 expect(defaultCockpitSelection(catalog)?.scope.nodeIds).toEqual(['north']);expect(catalog).toEqual(before);
 expect(accessibleCockpitSiteIds({...catalog,records:catalog.records.filter(record=>record.nativeSourceKind!=='site')})).toEqual([]);
});

describe('cockpit submitted contexts',()=>{
 it('keeps the latest request even when an aborted transport resolves late',async()=>{
  const first=deferred<CockpitSnapshot>(),second=deferred<CockpitSnapshot>();const signals:AbortSignal[]=[];
  const query=new CockpitQuery((r,signal)=>{signals.push(signal);return r.requestId==='one'?first.promise:second.promise;});
  const a=query.apply(request('one')),b=query.apply(request('two'));expect(signals[0].aborted).toBe(true);
  second.resolve(snapshot('two'));await b;first.resolve(snapshot('one'));await a;
  expect(query.getSnapshot().snapshot?.snapshotId).toBe('snapshot-two');
 });
 it('retains the complete old snapshot with its original context on refresh failure',async()=>{
  let fail=false;const query=new CockpitQuery(async r=>{if(fail)throw new Error('offline');return snapshot(r.requestId);});
  await query.apply(request('one'));fail=true;await query.apply(request('two'));
  expect(query.getSnapshot()).toMatchObject({phase:'error',error:'offline',snapshot:{requestId:'one'}});
 });
 it('detaches and freezes server results, including real zero and missing source observation',async()=>{
  const result=snapshot('one');const query=new CockpitQuery(async()=>result);await query.apply(request('one'));
  result.modules.kpis!.data!.values[0].value=99;
  expect(query.getSnapshot().snapshot?.modules.kpis?.data?.values[0].value).toBe(0);
  expect(query.getSnapshot().snapshot?.provenance.sourceLastObservedAt).toBeNull();
  expect(Object.isFrozen(query.getSnapshot().snapshot?.modules.kpis?.data?.values)).toBe(true);
 });
 it('freezes shared decoded evidence once while retaining its shared identity',async()=>{
  const result=snapshot('shared'),sources=result.modules.kpis!.data!.values[0].sourceIds;
  result.boundary.sourcePointIds=sources;
  const freezing=vi.spyOn(Object,'freeze');
  try{
   const query=new CockpitQuery(async()=>result);await query.apply(request('shared'));
   const saved=query.getSnapshot().snapshot!,shared=saved.boundary.sourcePointIds;
   expect(saved.modules.kpis!.data!.values[0].sourceIds).toBe(shared);
   expect(Object.isFrozen(shared)).toBe(true);
   expect(freezing.mock.calls.filter(([value])=>value===shared)).toHaveLength(1);
  }finally{freezing.mockRestore();}
 });
 it('stops after native session expiry rather than retrying in a loop',async()=>{
  let calls=0;const query=new CockpitQuery(async()=>{calls++;throw new ApiError('session_expired','sign in');});
  await query.apply(request('one'));await query.apply(request('two'));
  expect(query.getSnapshot().phase).toBe('sessionExpired');expect(calls).toBe(1);
 });
 it('ignores a disposed query without publishing its late response',async()=>{
  const pending=deferred<CockpitSnapshot>();const query=new CockpitQuery(()=>pending.promise);
  const work=query.apply(request('one'));query.cancel();pending.resolve(snapshot('one'));await work;
  expect(query.getSnapshot().snapshot).toBeUndefined();
 });
 it('rejects a mismatched response identity while preserving prior data',async()=>{
  const query=new CockpitQuery(async()=>snapshot('wrong'));await query.apply(request('one'));
  expect(query.getSnapshot().phase).toBe('error');expect(query.getSnapshot().snapshot).toBeUndefined();
 });
 it('uses real native site IDs and configured energy, without inventing buildings',()=>{
  const catalog:Catalog={version:'test',project:'test',user:{name:'test',canWrite:false},records:[{id:'site',kind:'space',name:'Campus',nativeSourceKind:'site'},{id:'water',kind:'category',name:'Water',unit:'m³'},{id:'electricity',kind:'category',name:'Electricity',unit:'kWh'},{id:'meter',kind:'meter',name:'Meter',pointId:'p',categoryId:'electricity'}]};
  expect(defaultCockpitSelection(catalog)).toEqual({scope:{dimension:'space',nodeIds:['site'],selectionIntent:'range'},categoryId:'electricity'});
  expect(defaultCockpitSelection({...catalog,records:[]})).toBeUndefined();
 });
});
