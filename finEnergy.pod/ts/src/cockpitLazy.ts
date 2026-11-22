import {cockpitModules,type CockpitFace,type CockpitRequest,type CockpitSnapshot} from './cockpitTypes';
import {absoluteCockpitRequest} from './cockpitNavigation';
import type {CockpitViewState} from './cockpitNavigation';
import {t} from './i18n';
export const cockpitInitialModules=['kpis','trend','issues','space'] as const;
export interface CockpitLazyState {loading:boolean;face?:CockpitFace|'full';snapshot?:CockpitSnapshot;errorSource?:string}
/** Absolute return-base transport does not mean the user edited its relative
 * preset. These labels only control the draft indicator, never API ranges. */
export function cockpitAppliedConditions(snapshot:CockpitSnapshot,previous?:CockpitViewState['appliedConditions']):NonNullable<CockpitViewState['appliedConditions']>{return snapshot.requestId.startsWith('return-base-')&&previous?previous:{preset:snapshot.context.time.preset,comparisonMode:snapshot.context.comparison?.mode||'none'};}
function freeze<T>(value:T):T{if(value&&typeof value==='object'&&!Object.isFrozen(value)){Object.values(value).forEach(freeze);Object.freeze(value);}return value;}
function invalid(source:string):Error{return Object.assign(new Error(t(source)),{sourceMessage:source});}
function compatible(a:CockpitSnapshot['context'],b:CockpitSnapshot['context']){
 return b.project===a.project&&b.configurationToken===a.configurationToken&&b.asOf===a.asOf&&b.time.from===a.time.from&&b.time.to===a.time.to&&
  b.time.period===a.time.period&&b.focusCategoryId===a.focusCategoryId&&(b.auxiliaryCategoryId??null)===(a.auxiliaryCategoryId??null)&&
  b.reportScope.dimension===a.reportScope.dimension&&b.reportScope.selectionIntent===a.reportScope.selectionIntent&&JSON.stringify(b.reportScope.nodeIds)===JSON.stringify(a.reportScope.nodeIds)&&
  (b.comparison?.from??null)===(a.comparison?.from??null)&&(b.comparison?.to??null)===(a.comparison?.to??null);
}
/** Observation-local cache; never graft independent reports into the homepage. */
export class CockpitLazyQuery {
 private base?:CockpitSnapshot;private epoch=0;private sequence=0;private desired?:CockpitFace|'full';private blockedSource?:string;
 private cache=new Map<CockpitFace|'full',CockpitSnapshot>();private pending=new Map<CockpitFace|'full',Promise<CockpitSnapshot|undefined>>();
 private controller?:AbortController;private tail:Promise<unknown>=Promise.resolve();
 private state:CockpitLazyState={loading:false};private listeners=new Set<()=>void>();
 constructor(private load:(request:CockpitRequest,signal:AbortSignal)=>Promise<CockpitSnapshot>){}
 getSnapshot=()=>this.state;
 subscribe=(listener:()=>void)=>{this.listeners.add(listener);return()=>{this.listeners.delete(listener);};};
 private publish(state:CockpitLazyState){this.state=state;this.listeners.forEach(listener=>listener());}
 reset(snapshot:CockpitSnapshot){this.cancel();this.base=snapshot;for(const face of ['space','time','endUse','organization','balance','efficiency'] as const)if(snapshot.modules[face])this.cache.set(face,snapshot);if(cockpitModules.every(m=>snapshot.modules[m]))this.cache.set('full',snapshot);
  // Historical complete snapshots predate the space module/token. They remain
  // usable as their original frozen export; no missing data is re-fetched.
  if(!snapshot.context.configurationToken){this.cache.set('space',snapshot);if(cockpitModules.filter(m=>m!=='space').every(m=>snapshot.modules[m]))this.cache.set('full',snapshot);}
 }
 cancel(){++this.epoch;this.controller?.abort();this.pending.clear();this.cache.clear();this.base=undefined;this.desired=undefined;this.blockedSource=undefined;this.publish({loading:false});}
 remember(snapshot:CockpitSnapshot){if(!this.base?.context.configurationToken||!compatible(this.base.context,snapshot.context))return false;const own=freeze(structuredClone(snapshot));for(const face of ['space','time','endUse','organization','balance','efficiency'] as const)if(own.modules[face])this.cache.set(face,own);return true;}
 async open(face:CockpitFace|'full'):Promise<CockpitSnapshot|undefined>{
  const base=this.base;if(!base)return;if(face!=='full')this.desired=face;
  const cached=this.cache.get(face);if(cached){if(face!=='full')this.publish({loading:false,face,snapshot:cached,errorSource:this.blockedSource});return cached;}
  if(this.blockedSource){this.publish({loading:false,face,errorSource:this.blockedSource});throw invalid(this.blockedSource);}
  const existing=this.pending.get(face);if(existing)return existing;
  const epoch=this.epoch;if(face!=='full')this.publish({loading:true,face});
  const run=async()=>{
   if(epoch!==this.epoch||(face!=='full'&&this.desired!==face))return;
   const controller=new AbortController();this.controller=controller;
   try{
    const token=base.context.configurationToken;if(!token)throw invalid('此快照缺少配置版本，请刷新首页。');
    const request={...absoluteCockpitRequest(base),requestId:'face-'+(++this.sequence),expectedConfigurationToken:token,
     modules:face==='full'?[...cockpitModules]:[face]} satisfies CockpitRequest;
    const result=await this.load(request,controller.signal);
    if(epoch!==this.epoch||controller.signal.aborted)return;
    if(result.schemaVersion!==1||result.requestId!==request.requestId||!compatible(base.context,result.context)||
     !request.modules.every(m=>Object.hasOwn(result.modules,m))){this.blockedSource='配置已变化，请刷新首页后重新打开此视角。';throw invalid(this.blockedSource);}
    const saved=freeze(structuredClone(result));this.cache.set(face,saved);
    if(this.desired===face)this.publish({loading:false,face,snapshot:saved});return saved;
   }catch(error){
    if(epoch!==this.epoch||controller.signal.aborted)return;
    const source=error&&typeof error==='object'&&'sourceMessage'in error&&typeof error.sourceMessage==='string'?error.sourceMessage:'该视角读取失败，可再次选择重试。';
    if(error&&typeof error==='object'&&'code'in error&&error.code==='COCKPIT_CONFIGURATION_CHANGED')this.blockedSource=source;
    if(this.desired===face)this.publish({loading:false,face,errorSource:source});throw error;
   }
  };
  const opening=this.tail.then(run);this.tail=opening.catch(()=>undefined);this.pending.set(face,opening);
  try{return await opening;}finally{if(epoch===this.epoch)this.pending.delete(face);}
 }
}
