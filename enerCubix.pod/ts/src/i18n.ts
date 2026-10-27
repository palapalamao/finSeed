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
export const localeStorageKey='enerCubix.locale.v1';
type BrowserLanguage={language?:string;languages?:readonly string[]};
const isLocale=(value:unknown):value is Locale=>typeof value==='string'&&Object.hasOwn(languageDefinitions,value);

function preferenceStorage():Storage|undefined{
 try{return typeof localStorage==='undefined'?undefined:localStorage;}catch{return undefined;}
}

export function readLanguagePreference(storage:Pick<Storage,'getItem'>|undefined=preferenceStorage(),search=typeof location==='undefined'?'':location.search):LanguagePreference{
 const override=new URLSearchParams(search).get('enerCubixLang');
 if(override==='auto'||isLocale(override))return override;
 try{const saved=storage?.getItem(localeStorageKey);return isLocale(saved)?saved:'auto';}catch{return 'auto';}
}

/** Browsers normally inherit the OS language; the first browser preference wins. */
export function detectLocale(browser:BrowserLanguage={},systemLanguage=''):Locale{
 const preferred=(browser.language?.trim()||browser.languages?.find(value=>value.trim())||systemLanguage).toLowerCase().replaceAll('_','-');
 return (Object.keys(languageDefinitions) as Locale[]).find(value=>value.split('-')[0]===preferred.split('-')[0])||'en-US';
}

// Resolve once per page load so module-level labels, controls and exports agree.
export const languagePreference=readLanguagePreference();
export const locale=languagePreference==='auto'?detectLocale(typeof navigator==='undefined'?{}:navigator,Intl.DateTimeFormat().resolvedOptions().locale):languagePreference;
const activeLanguage=languageDefinitions[locale];
dayjs.locale(activeLanguage.dayjsLocale);

export function changeLanguage(preference:LanguagePreference){
 if(preference===languagePreference)return;
 const next=new URL(location.href);let saved=false;
 try{const storage=preferenceStorage();if(storage){if(preference==='auto')storage.removeItem(localeStorageKey);else storage.setItem(localeStorageKey,preference);saved=true;}}catch{/* The URL retains this tab's selection if browser storage is blocked. */}
 if(saved)next.searchParams.delete('enerCubixLang');else next.searchParams.set('enerCubixLang',preference);
 if(next.href===location.href)location.reload();else location.replace(next.href);
}

export function t(source:string,...values:unknown[]):string{
 const message=locale==='zh-CN'?source:activeLanguage.messages[source]??activeLanguage.serverMessages[source]??englishMessages[source]??serverMessages[source]??source;
 return message.replace(/\{(\d+)\}/g,(token,index:string)=>Number(index)<values.length?String(values[Number(index)]):token);
}

const serviceMessages={...serverMessages,...activeLanguage.serverMessages};
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
  return ({'EnerCubix 调度记录标识已被其他记录占用':'能源魔方调度记录标识已被其他记录占用','设备已被其他 EnerCubix 配置占用':'设备已被其他能源魔方配置占用'} as Record<string,string>)[source]??source;
 }
 const exact=activeLanguage.messages[source]??serviceMessages[source]??englishMessages[source];
 if(exact)return exact;
 for(const {pattern,message,translateReason} of serverPatterns){const match=source.match(pattern);if(match)return message.replace(/\{(\d+)\}/g,(_,index:string)=>translateReason&&index==='1'?t(match[2]):match[Number(index)+1]);}
 return source;
}

export function initializeLocale(){
 document.documentElement.lang=locale;
 document.title=t('能源魔方 · 楼宇能源分析');
}
