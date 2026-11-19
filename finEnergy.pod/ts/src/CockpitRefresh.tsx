import {useEffect,useMemo,useSyncExternalStore} from 'react';
import {Select} from 'antd';
import type {CockpitQuery} from './cockpitQuery';
import {CockpitAutoRefresh,browserRefreshLock,refreshMinutes,refreshPreferenceKey,type AutoRefreshState} from './cockpitAutoRefresh';
import {locale,t} from './i18n';
export function useCockpitRefresh(query:CockpitQuery,user:string,project:string){
 const controller=useMemo(()=>new CockpitAutoRefresh({query,user,project,lock:browserRefreshLock(),storage:{getItem:key=>window.localStorage.getItem(key),setItem:(key,value)=>window.localStorage.setItem(key,value),removeItem:key=>window.localStorage.removeItem(key)}}),[query,user,project]);
 const state=useSyncExternalStore(controller.subscribe,controller.getSnapshot,controller.getSnapshot);
 useEffect(()=>{const visible=()=>controller.setPaused('hidden',document.hidden),before=()=>controller.setPaused('printing',true),after=()=>controller.setPaused('printing',false),storage=(event:StorageEvent)=>{if(event.key===refreshPreferenceKey(user,project))controller.reloadPreference();};controller.start();visible();document.addEventListener('visibilitychange',visible);window.addEventListener('beforeprint',before);window.addEventListener('afterprint',after);window.addEventListener('storage',storage);return()=>{document.removeEventListener('visibilitychange',visible);window.removeEventListener('beforeprint',before);window.removeEventListener('afterprint',after);window.removeEventListener('storage',storage);controller.stop();};},[controller,user,project]);
 return {controller,state};
}
export function refreshStatus(state:AutoRefreshState){
 if(state.unavailable==='storage')return t('浏览器存储不可用，已保持手动刷新。');
 if(state.unavailable==='locking')return t('浏览器不支持可靠的跨窗口互斥，已保持手动刷新。');
 if(!state.minutes)return t('手动刷新');
 if(state.pause==='error')return t('自动刷新因查询失败已暂停；手动刷新成功后恢复。');
 if(state.pause==='sessionExpired')return t('会话已失效，自动刷新已停止。');
 if(state.pause==='export'||state.pause==='printing')return t('导出或打印期间暂停自动刷新。');
 if(state.pause==='hidden'||state.pause==='route')return t('页面不可见时暂停自动刷新。');
 if(state.running)return t('正在按已应用条件自动刷新。');
 if(state.pause==='query')return t('等待当前查询完成，不叠加自动请求。');
 if(state.skippedOtherTab)return t('另一窗口正在查询，本轮自动刷新已跳过。');
 return t('每 {0} 分钟自动刷新已应用条件；下次 {1}。',state.minutes,state.nextAt?new Date(state.nextAt).toLocaleTimeString(locale):'—');
}
// Avoid a stale leave-animation portal when the global reduced-motion CSS suppresses animationend.
export function CockpitRefreshControls({controller,state}:{controller:CockpitAutoRefresh;state:AutoRefreshState}){return <div className="cockpit-refresh-controls"><label>{t('浏览器页面自动刷新')}<Select transitionName="" aria-label={t('浏览器页面自动刷新')} value={state.minutes} disabled={!!state.unavailable||state.pause==='sessionExpired'} onChange={value=>controller.setMinutes(value)} options={refreshMinutes.map(value=>({value,label:value?t('每 {0} 分钟',value):t('手动刷新')}))}/></label><p role="status">{refreshStatus(state)}</p><p>{t('仅更新页面，不修改后台总表计算频率；自动请求使用已应用条件，不提交草稿。')}</p></div>;}
