import type {CockpitRequest,CockpitSnapshot} from './cockpitTypes';
import type {Catalog} from './types';
import {serverMessage,t} from './i18n';
export interface CockpitQueryState {phase:'idle'|'loading'|'refreshing'|'ready'|'error'|'sessionExpired';snapshot?:CockpitSnapshot;error?:string;errorSource?:string}
export function cockpitQueryError(state:CockpitQueryState):string{return state.errorSource?serverMessage(state.errorSource):state.error||'';}
function freeze<T>(value:T):T {if(value&&typeof value==='object'&&!Object.isFrozen(value)){Object.values(value).forEach(freeze);Object.freeze(value);}return value;}
export class CockpitQuery {
 private state:CockpitQueryState={phase:'idle'};
 private sequence=0;
 private controller?:AbortController;
 private listeners=new Set<()=>void>();
 constructor(private load:(request:CockpitRequest,signal:AbortSignal)=>Promise<CockpitSnapshot>){}
 getSnapshot=()=>this.state;
 subscribe=(listener:()=>void)=>{this.listeners.add(listener);return()=>{this.listeners.delete(listener);};};
 private publish(state:CockpitQueryState){this.state=state;this.listeners.forEach(listener=>listener());}
 async apply(request:CockpitRequest){
  if(this.state.phase==='sessionExpired')return;
  const sequence=++this.sequence;this.controller?.abort();const controller=new AbortController();this.controller=controller;
  this.publish({phase:this.state.snapshot?'refreshing':'loading',snapshot:this.state.snapshot});
  try{
   const result=await this.load(structuredClone(request),controller.signal);
   if(sequence!==this.sequence||controller.signal.aborted)return;
   if(result.schemaVersion!==1||result.requestId!==request.requestId)throw Object.assign(new Error(t('驾驶舱响应与当前查询不一致，请重新查询。')),{sourceMessage:'驾驶舱响应与当前查询不一致，请重新查询。'});
   this.publish({phase:'ready',snapshot:freeze(structuredClone(result))});
  }catch(error){
   if(sequence!==this.sequence||controller.signal.aborted)return;
   const code=error&&typeof error==='object'&&'code'in error?error.code:undefined;
   const expired=code==='session_expired'||code==='unauthorized';
   const source=error&&typeof error==='object'&&'sourceMessage'in error&&typeof error.sourceMessage==='string'?error.sourceMessage:code==='network'?'无法连接 FIN，请检查网络与当前会话。':!(error instanceof Error)?'无法读取驾驶舱，请检查当前 FIN 会话。':undefined;
   this.publish({phase:expired?'sessionExpired':'error',snapshot:this.state.snapshot,errorSource:source,error:error instanceof Error?error.message:t('无法读取驾驶舱，请检查当前 FIN 会话。')});
  }
 }
 restore(snapshot:CockpitSnapshot){this.cancel();this.publish({phase:'ready',snapshot:freeze(structuredClone(snapshot))});}
 cancel(){++this.sequence;this.controller?.abort();if(this.state.phase==='loading'||this.state.phase==='refreshing')this.publish({phase:this.state.snapshot?'ready':'idle',snapshot:this.state.snapshot});}
}
export function defaultCockpitSelection(catalog:Catalog):{scope:CockpitRequest['reportScope'];categoryId:string}|undefined{
 const meters=catalog.records.filter(r=>['meter','totalMeter'].includes(r.kind)&&r.pointId&&!r.canonicalId);
 const categories=catalog.records.filter(r=>r.kind==='category'&&meters.some(m=>m.categoryId===r.id));
 const category=categories.find(r=>r.unit==='kWh')||categories[0];if(!category?.id)return;
 const spaces=catalog.records.filter(r=>r.kind==='space'&&!r.nativeHidden);
 const site=spaces.find(r=>r.nativeSourceKind==='site')||spaces.find(r=>!r.parentId);
 const meter=meters.find(r=>r.categoryId===category.id);
 if(!site?.id&&!meter?.id)return;
 return {scope:{dimension:site?'space':'metering',nodeIds:[String(site?.id||meter!.id)],selectionIntent:'range'},categoryId:category.id};
}
