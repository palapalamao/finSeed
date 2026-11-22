import {readPreference} from './preferences';
import dayjs from 'dayjs';
import 'dayjs/locale/zh-cn.js';
import {englishMessages} from './messages';
import {chineseServerMessages,serverMessages} from './serverMessages';

const sourceMessages:Record<string,string>={};
// Add a translated dictionary and date locale here to register another language.
export const languageDefinitions={
 'zh-CN':{label:'中文',dayjsLocale:'zh-cn',messages:sourceMessages,serverMessages:sourceMessages},
 'en-US':{label:'English',dayjsLocale:'en',messages:englishMessages,serverMessages}
};
export type Locale=keyof typeof languageDefinitions;
export type LanguagePreference=Locale|'auto';
export let languagePreference:LanguagePreference='auto';
let preferenceKey:string|undefined;
let finUserLanguage='en-US';
const localeListeners=new Set<()=>void>();
export function subscribeLocale(listener:()=>void){localeListeners.add(listener);return()=>{localeListeners.delete(listener);};}
export const localeSnapshot=()=>locale;
export function localizedRecord<T extends Record<string,string>>(factory:()=>T):T{const record=factory();subscribeLocale(()=>Object.assign(record,factory()));return record;}
const isLocale=(value:unknown):value is Locale=>typeof value==='string'&&Object.hasOwn(languageDefinitions,value);
/** FIN's authenticated request locale is the default language source. */
export function resolveFinLocale(language:string):Locale{
 const preferred=language.trim().toLowerCase().replaceAll('_','-');
 return (Object.keys(languageDefinitions) as Locale[]).find(value=>value.split('-')[0]===preferred.split('-')[0])||'en-US';
}

// main.tsx initializes this before importing any modules with translated labels.
export let locale:Locale='en-US';
let activeLanguage=languageDefinitions[locale];

export function translateFor(language:Locale,source:string,...values:unknown[]):string{
 const dictionary=languageDefinitions[language];
 const message=language==='zh-CN'?source:dictionary.messages[source]??dictionary.serverMessages[source]??englishMessages[source]??serverMessages[source]??source;
 return message.replace(/\{(\d+)\}/g,(token,index:string)=>Number(index)<values.length?String(values[Number(index)]):token);
}
export function t(source:string,...values:unknown[]):string{
 const message=locale==='zh-CN'?source:activeLanguage.messages[source]??activeLanguage.serverMessages[source]??englishMessages[source]??serverMessages[source]??source;
 return message.replace(/\{(\d+)\}/g,(token,index:string)=>Number(index)<values.length?String(values[Number(index)]):token);
}

const serviceMessages=serverMessages;
const serverPatterns=Object.entries(serviceMessages).filter(([source])=>/\{\d+\}/.test(source)).map(([source,message])=>({
 pattern:new RegExp('^'+source.split(/\{\d+\}/).map(part=>part.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('(.+?)')+'$'),message,
 translateReason:source.startsWith('{0}：{1}，至少需要')
}));
const chineseServerPatterns=Object.entries(chineseServerMessages).filter(([source])=>/\{\d+\}/.test(source)).map(([source,message])=>({pattern:new RegExp('^'+source.split(/\{\d+\}/).map(part=>part.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')).join('(.+?)')+'$'),message}));

export function serverMessage(source:string):string{
 if(source.startsWith('虚拟总表“')&&source.includes('\n'))return source.split('\n').map(serverMessage).join('\n');
 if(locale==='zh-CN'){
  if(chineseServerMessages[source])return chineseServerMessages[source];
  for(const {pattern,message}of chineseServerPatterns){const match=source.match(pattern);if(match)return message.replace(/\{(\d+)\}/g,(_,index:string)=>match[Number(index)+1]);}
  return ({'FinEnergy 调度记录标识已被其他记录占用':'FIN 能源管理调度记录标识已被其他记录占用','设备已被其他 FinEnergy 配置占用':'设备已被其他 FIN 能源管理配置占用'} as Record<string,string>)[source]??source;
 }
 const exact=activeLanguage.messages[source]??serviceMessages[source]??englishMessages[source];
 if(exact)return exact;
 for(const {pattern,message,translateReason} of serverPatterns){const match=source.match(pattern);if(match)return message.replace(/\{(\d+)\}/g,(_,index:string)=>translateReason&&index==='1'?t(match[2]):match[Number(index)+1]);}
 return source;
}

export function changeLanguage(preference:LanguagePreference,{inPlace=false}:{inPlace?:boolean}={}){
 if(!preferenceKey||preference===languagePreference||(preference!=='auto'&&!isLocale(preference)))return;
 try{
  if(preference==='auto')localStorage.removeItem(preferenceKey);else localStorage.setItem(preferenceKey,preference);
 }catch{throw new Error(t('无法保存语言设置，请检查浏览器的站点存储权限。'));}
 if(inPlace){languagePreference=preference;applyLocale();localeListeners.forEach(listener=>listener());}else location.reload();
}

export function initializeLocale(finLanguage:string,username?:string){
 finUserLanguage=finLanguage;
 preferenceKey=username?'finEnergy.locale.v2.'+encodeURIComponent(username):undefined;
 languagePreference='auto';
 try{const saved=preferenceKey?readPreference(localStorage,preferenceKey,'enerCubix.locale.v2.'+encodeURIComponent(username!)):null;if(isLocale(saved))languagePreference=saved;}catch{/* Keep the authenticated FIN language when storage is unavailable. */}
 applyLocale();
}
function applyLocale(){
 locale=languagePreference==='auto'?resolveFinLocale(finUserLanguage):languagePreference;
 activeLanguage=languageDefinitions[locale];
 dayjs.locale(activeLanguage.dayjsLocale);
 if(typeof document!=='undefined'){
  document.documentElement.lang=locale;
  document.title=t('FIN 能源管理 · 楼宇能源分析');
 }
}

// Cockpit observation-local loading; dictionaries remain open to future locales.
Object.assign(englishMessages,{
 '此快照缺少配置版本，请刷新首页。':'This snapshot has no configuration version. Refresh the homepage.',
 '配置已变化，请刷新首页后重新打开此视角。':'Configuration changed. Refresh the homepage before reopening this view.',
 '该视角读取失败，可再次选择重试。':'This view could not be loaded. Select it again to retry.',
 '此视角正在按需读取…':'Loading this view…',
 '视角独立快照：{0}；历史观察：{1} 至 {2}。':'Independent view snapshot: {0}; history observed from {1} to {2}.',
 '该视角使用独立快照，核心指标和趋势保留首页快照。':'This view has its own snapshot. Core indicators and the trend retain the homepage snapshot.',
 '正在生成完整冻结汇报…':'Preparing a complete frozen report…'
});
Object.assign(serverMessages,{cockpitConfigurationChanged:'Configuration changed. Refresh the homepage before reopening this view.'});
Object.assign(chineseServerMessages,{cockpitConfigurationChanged:'配置已变化，请刷新首页后重新打开此视角。'});
