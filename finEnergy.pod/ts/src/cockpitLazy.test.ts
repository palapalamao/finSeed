import {expect,it,vi} from 'vitest';
import {CockpitLazyQuery,cockpitAppliedConditions} from './cockpitLazy';
import {cockpitModules,type CockpitRequest,type CockpitSnapshot} from './cockpitTypes';
const token='a'.repeat(64);
function fixture(id='base'):CockpitSnapshot{return {schemaVersion:1,requestId:id,snapshotId:id,generatedAt:'2026-11-22T00:00:00Z',
 context:{project:'test',projectTimeZone:'UTC',configurationToken:token,reportScope:{dimension:'space',nodeIds:['site'],selectionIntent:'range'},focusCategoryId:'c',asOf:'2026-11-22T00:00:00Z',time:{preset:'thisMonth',period:'day',from:'2026-11-01T00:00:00Z',to:'2026-11-22T00:00:00Z'},comparison:{mode:'presetDefault',from:'2025-11-01T00:00:00Z',to:'2025-11-22T00:00:00Z'}},
 boundary:{id:'boundary',meterIds:['m'],sourcePointIds:['p'],aggregateAllowed:true,overlaps:[],excluded:[]},modules:{kpis:{status:'ok'},trend:{status:'ok'},space:{status:'ok'},issues:{status:'ok'}},reports:{},provenance:{configFingerprint:'f',relationshipBasis:'currentConfiguration',historyBasis:'ownPrimaryPointRaw',historyObservedFrom:'',historyObservedTo:'',sourceLastObservedAt:null,configRefs:[]},quality:[],capabilities:{canRead:true,canManage:false,availableFaces:[]},limitations:[]};}
function answer(r:CockpitRequest):CockpitSnapshot{return {...fixture(r.requestId),modules:Object.fromEntries(r.modules.map(m=>[m,{status:'ok'}]))};}
function deferred<T>(){let resolve!:(v:T)=>void;return {promise:new Promise<T>(yes=>{resolve=yes;}),resolve};}
it('loads only a requested face, reuses it, and freezes every independent result',async()=>{
 const calls:CockpitRequest[]=[];const query=new CockpitLazyQuery(async r=>{calls.push(r);return answer(r);});const base=fixture();query.reset(base);
 expect(await query.open('space')).toMatchObject({snapshotId:'base'});expect(calls).toHaveLength(0);
 const first=await query.open('time');expect(calls).toHaveLength(1);
 expect(calls[0]).toMatchObject({asOf:base.context.asOf,expectedConfigurationToken:token,time:{preset:'custom',from:base.context.time.from,to:base.context.time.to},comparison:{mode:'custom',from:'2025-11-01T00:00:00Z',to:'2025-11-22T00:00:00Z'}});
 expect(calls[0].modules).toEqual(['time']);expect(Object.isFrozen(first)).toBe(true);
 expect(await query.open('time')).toBe(first);expect(calls).toHaveLength(1);expect(base.modules.time).toBeUndefined();
 const full=await query.open('full');expect(calls).toHaveLength(2);expect(calls[1].modules).toEqual([...cockpitModules]);expect(full?.snapshotId).not.toBe(first?.snapshotId);
});
it('rejects changed configuration and mismatched period without altering the base snapshot',async()=>{
 const base=fixture();const loader=vi.fn(async(r:CockpitRequest)=>({...answer(r),context:{...fixture().context,configurationToken:'b'.repeat(64)}}));
 const query=new CockpitLazyQuery(loader);query.reset(base);await expect(query.open('time')).rejects.toThrow();
 expect(await query.open('space')).toMatchObject({snapshotId:'base'});expect(base.modules.time).toBeUndefined();
});
it('aborts a retired observation and never caches its late response',async()=>{
 const pending=deferred<CockpitSnapshot>();let sent!:CockpitRequest,signal!:AbortSignal;
 const query=new CockpitLazyQuery((r,s)=>{sent=r;signal=s;return pending.promise;});query.reset(fixture());
 const opening=query.open('time');await Promise.resolve();query.reset(fixture('new-base'));expect(signal.aborted).toBe(true);
 pending.resolve(answer(sent));expect(await opening).toBeUndefined();expect(await query.open('space')).toMatchObject({snapshotId:'new-base'});
});
it('serializes distinct face requests instead of competing for the native project gate',async()=>{
 const first=deferred<CockpitSnapshot>();const calls:CockpitRequest[]=[];const query=new CockpitLazyQuery(async r=>{calls.push(r);return calls.length===1?first.promise:answer(r);});query.reset(fixture());
 const a=query.open('time');await Promise.resolve();const b=query.open('balance');await Promise.resolve();expect(calls).toHaveLength(1);
 first.resolve(answer(calls[0]));await a;await b;expect(calls).toHaveLength(2);expect(calls[1].modules).toContain('balance');
});
it('rehydrates a returned independent face without copying it into the restored core',async()=>{
 const load=vi.fn(async(r:CockpitRequest)=>answer(r));const query=new CockpitLazyQuery(load);
 const partial={...fixture('saved-time'),modules:{time:{status:'ok' as const}}};
 const core=fixture('new-core');query.reset(core);expect(query.remember(partial)).toBe(true);
 expect(await query.open('time')).toMatchObject({snapshotId:'saved-time'});expect(load).not.toHaveBeenCalled();
 expect(core.modules.time).toBeUndefined();
 expect(query.remember({...partial,context:{...partial.context,asOf:'2026-11-23T00:00:00Z'}})).toBe(false);
});
it('cancels queued complete export data without cancelling the selected face',async()=>{
 const pending=deferred<CockpitSnapshot>();let faceRequest!:CockpitRequest;
 const load=vi.fn((request:CockpitRequest)=>{faceRequest=request;return pending.promise;});
 const query=new CockpitLazyQuery(load);query.reset(fixture());
 const face=query.open('time');await Promise.resolve();
 const complete=query.open('full');
 expect(query.getSnapshot().fullStartedAt).toBeTypeOf('number');
 query.cancelFull();
 expect(query.getSnapshot()).toMatchObject({face:'time',loading:true,fullStartedAt:undefined});
 pending.resolve(answer(faceRequest));
 expect(await face).toBeDefined();
 expect(await complete).toBeUndefined();
 expect(load).toHaveBeenCalledTimes(1);
});
it('requires a fresh base after a known configuration conflict and retains old cached snapshots as old',async()=>{
 const load=vi.fn(async()=>{throw Object.assign(new Error('changed'),{code:'COCKPIT_CONFIGURATION_CHANGED',sourceMessage:'cockpitConfigurationChanged'});});
 const query=new CockpitLazyQuery(load);query.reset(fixture());await expect(query.open('time')).rejects.toThrow();
 await expect(query.open('balance')).rejects.toThrow();expect(load).toHaveBeenCalledTimes(1);
 await query.open('space');expect(query.getSnapshot().errorSource).toBe('cockpitConfigurationChanged');
 query.reset(fixture('refresh'));await expect(query.open('time')).rejects.toThrow();expect(load).toHaveBeenCalledTimes(2);
});
it('retains applied relative labels after absolute base rehydration but uses fresh labels after manual refresh',()=>{
 const original={preset:'thisMonth' as const,comparisonMode:'presetDefault' as const};
 const returned={...fixture('return-base-1'),context:{...fixture().context,time:{...fixture().context.time,preset:'custom' as const},comparison:{mode:'custom' as const,from:'2025-11-01T00:00:00Z',to:'2025-11-22T00:00:00Z'}}};
 expect(cockpitAppliedConditions(returned,original)).toBe(original);
 expect(cockpitAppliedConditions({...returned,requestId:'cockpit-2'},original)).toEqual({preset:'custom',comparisonMode:'custom'});
});
