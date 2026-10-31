import {cockpitModules,type CockpitRequest,type CockpitSnapshot} from './cockpitTypes';
import type {CockpitQuery} from './cockpitQuery';
export const refreshMinutes=[0,5,10,15,30] as const;
export type RefreshMinutes=typeof refreshMinutes[number];
export type RefreshLock=(key:string,run:()=>Promise<void>)=>Promise<boolean>;
export interface AutoRefreshState {minutes:RefreshMinutes;nextAt?:number;running:boolean;pause?:string;unavailable?:'storage'|'locking';skippedOtherTab:boolean}
export const refreshPreferenceKey=(user:string,project:string)=>'enerCubix.cockpit.refresh.v1.'+encodeURIComponent(user)+'/'+encodeURIComponent(project);
export function freshCockpitRequest(snapshot:CockpitSnapshot,requestId:string):CockpitRequest{
 const c=snapshot.context,custom=c.time.preset==='custom';return {schemaVersion:1,requestId,reportScope:structuredClone(c.reportScope),focusCategoryId:c.focusCategoryId,...(c.auxiliaryCategoryId?{auxiliaryCategoryId:c.auxiliaryCategoryId}:{}),time:custom?{preset:'custom',period:c.time.period,from:c.time.from,to:c.time.to}:{preset:c.time.preset,period:c.time.period},comparison:c.comparison?.mode==='custom'?structuredClone(c.comparison):{mode:c.comparison?.mode||'none'},modules:cockpitModules.filter(key=>Object.hasOwn(snapshot.modules,key))};
}
export function browserRefreshLock():RefreshLock|undefined{
 if(typeof navigator==='undefined'||!navigator.locks)return;
 return (name,run)=>navigator.locks.request(name,{ifAvailable:true},async lock=>{if(!lock)return false;await run();return true;});
}
interface Options {query:CockpitQuery;storage:Pick<Storage,'getItem'|'setItem'|'removeItem'>;user:string;project:string;lock?:RefreshLock;now?:()=>number}
/** One optional page timer. Web Locks skip a competing tab, rather than queueing stale work. */
export class CockpitAutoRefresh {
 private state:AutoRefreshState={minutes:0,running:false,skippedOtherTab:false};
 private listeners=new Set<()=>void>();private timer?:ReturnType<typeof setTimeout>;private started=false;private unsubscribe?:()=>void;private paused=new Set<string>();private errorPause=false;private ownedRequest?:string;private sequence=0;private previousPhase:string;private key:string;private now:()=>number;
 constructor(private options:Options){this.key=refreshPreferenceKey(options.user,options.project);this.now=options.now||Date.now;this.previousPhase=options.query.getSnapshot().phase;try{const raw=options.storage.getItem(this.key);options.storage.setItem(this.key,raw??'0');if(raw===null)options.storage.removeItem(this.key);const value=Number(raw);if(refreshMinutes.includes(value as RefreshMinutes))this.state.minutes=value as RefreshMinutes;}catch{this.state.unavailable='storage';}if(!options.lock&&!this.state.unavailable)this.state.unavailable='locking';if(this.state.unavailable)this.state.minutes=0;}
 getSnapshot=()=>this.state;
 subscribe=(listener:()=>void)=>{this.listeners.add(listener);return()=>{this.listeners.delete(listener);};};
 private publish(patch:Partial<AutoRefreshState>={}){const phase=this.options.query.getSnapshot().phase;this.state={...this.state,...patch,pause:phase==='sessionExpired'?'sessionExpired':this.errorPause?'error':[...this.paused][0]||(['loading','refreshing'].includes(phase)?'query':undefined)};this.listeners.forEach(listener=>listener());}
 private clear(){if(this.timer!==undefined)clearTimeout(this.timer);this.timer=undefined;}
 private arm(){this.clear();this.publish();const q=this.options.query.getSnapshot();if(!this.started||!this.state.minutes||this.state.unavailable||this.state.running||this.state.pause||q.phase!=='ready'||!q.snapshot)return;if(this.state.nextAt===undefined)this.publish({nextAt:this.now()+this.state.minutes*60000});this.timer=setTimeout(()=>{this.timer=undefined;void this.tick();},Math.max(0,this.state.nextAt!-this.now()));}
 private cancelOwned(){if(this.ownedRequest&&this.options.query.getSnapshot().pendingRequestId===this.ownedRequest)this.options.query.cancel();}
 start(){if(this.started)return;this.started=true;this.unsubscribe=this.options.query.subscribe(()=>{const phase=this.options.query.getSnapshot().phase;if(phase==='error')this.errorPause=true;if(phase==='ready'&&this.previousPhase!=='ready'&&!this.state.running){this.errorPause=false;this.publish({nextAt:this.state.minutes?this.now()+this.state.minutes*60000:undefined,skippedOtherTab:false});}this.previousPhase=phase;this.arm();});this.arm();}
 stop(){this.started=false;this.clear();this.unsubscribe?.();this.unsubscribe=undefined;this.cancelOwned();}
 setMinutes(value:number){if(!refreshMinutes.includes(value as RefreshMinutes))return;if(this.state.unavailable){this.publish({minutes:0});return;}try{this.options.storage.setItem(this.key,String(value));}catch{this.cancelOwned();this.publish({minutes:0,unavailable:'storage',nextAt:undefined});this.clear();return;}if(value===0)this.cancelOwned();this.errorPause=value!==0&&this.options.query.getSnapshot().phase==='error';this.publish({minutes:value as RefreshMinutes,nextAt:value?this.now()+value*60000:undefined,skippedOtherTab:false});this.arm();}
 reloadPreference(){try{const value=Number(this.options.storage.getItem(this.key));this.setMinutes(refreshMinutes.includes(value as RefreshMinutes)?value:0);}catch{this.cancelOwned();this.publish({minutes:0,unavailable:'storage',nextAt:undefined});this.clear();}}
 setPaused(reason:string,paused:boolean){if(paused){this.paused.add(reason);this.cancelOwned();}else this.paused.delete(reason);this.arm();}
 private async tick(){const {query,lock}=this.options;if(!this.started||this.state.pause||this.state.running||!this.state.minutes||query.getSnapshot().phase!=='ready')return;this.publish({running:true,skippedOtherTab:false});try{const acquired=await lock!(this.key,async()=>{const current=query.getSnapshot();if(!this.started||this.paused.size||this.errorPause||current.phase!=='ready'||!current.snapshot)return;this.ownedRequest='auto-'+this.now()+'-'+(++this.sequence);await query.apply(freshCockpitRequest(current.snapshot,this.ownedRequest));});this.publish({skippedOtherTab:!acquired});}catch{this.publish({minutes:0,unavailable:'locking'});}finally{this.ownedRequest=undefined;this.publish({running:false,nextAt:this.state.minutes?this.now()+this.state.minutes*60000:undefined});this.arm();}}
}
