import type {ReportSnapshot} from './types';
import {t,locale} from './i18n';

export type CoverageStatus='complete'|'partial'|'missing'|'invalid'|'na'|'substituted'|'future'|'ongoing';
export interface CoverageInterval {intervalStart:string;intervalEnd:string;value:number|null;valueType:string;quality:string}
export interface CoveragePeriod {
 key:string;from:string;to:string;value:number|null;valueType:string;quality:string;status:CoverageStatus;
 coveredSeconds:number;intervalCount:number;intervals:CoverageInterval[];detailsTruncated:boolean;slots:number;
}
export interface CoverageGroup {
 key:string;nodeId:string;pointId:string;name:string;source:string;unit:string;periods:CoveragePeriod[];
 coveredSeconds:number|null;intervalCount:number|null;intervals:CoverageInterval[];detailsTruncated:boolean;overlapping:boolean;
 firstReading?:string;lastReading?:string;
}
const maps=(value:unknown):Record<string,unknown>[]=>Array.isArray(value)?value.filter((v):v is Record<string,unknown>=>!!v&&typeof v==='object'):[];
const number=(value:unknown)=>typeof value==='number'&&Number.isFinite(value)?value:null;
const count=(value:unknown)=>Math.max(0,number(value)??0);
const string=(value:unknown)=>typeof value==='string'?value:'';
const good=new Set(['ok','good','derived','cleaned','corrected','estimated']);
export const coverageStatusText=(status:CoverageStatus)=>t(({complete:'完整覆盖',partial:'部分覆盖',missing:'缺测',invalid:'异常',na:'NA',substituted:'含替代值',future:'未到时间',ongoing:'尚未结束'} as const)[status]);
export function coverageDuration(seconds:number|null):string{
 if(seconds===null)return t('详见时段');
 const rounded=Math.round(seconds),hours=Math.floor(rounded/3600),minutes=Math.floor(rounded%3600/60),rest=rounded%60;
 if(hours)return rest?t('{0} 小时 {1} 分 {2} 秒',hours,minutes,rest):t('{0} 小时 {1} 分',hours,minutes);
 if(minutes)return rest?t('{0} 分 {1} 秒',minutes,rest):t('{0} 分钟',minutes);
 return t('{0} 秒',new Intl.NumberFormat(locale,{maximumFractionDigits:2}).format(seconds));
}
function status(row:Record<string,unknown>,from:string,to:string,asOf:number):CoverageStatus{
 const value=number(row.knownValue),quality=string(row.knownQuality);
 if(row.knownValueType==='na'||quality==='na')return 'na';
 if(value!==null){
  if(value<0)return 'invalid';
  if(quality==='substituted')return 'substituted';
  return good.has(quality)&&count(row.coveredSeconds)>=(Date.parse(to)-Date.parse(from))/1000&&Date.parse(to)<=asOf?'complete':'partial';
 }
 if(['missing','incompleteInterval',''].includes(quality)){
  if(Date.parse(from)>=asOf)return 'future';
  if(Date.parse(to)>asOf)return 'ongoing';
  return 'missing';
 }
 return 'invalid';
}
function uniqueIntervals(rows:CoverageInterval[]):CoverageInterval[]{
 const seen=new Set<string>();return rows.filter(row=>{const key=JSON.stringify([row.intervalStart,row.intervalEnd,row.value,row.valueType,row.quality]);if(seen.has(key))return false;seen.add(key);return true;}).sort((a,b)=>Date.parse(a.intervalStart)-Date.parse(b.intervalStart));
}
export function coverageGroups(snapshot:ReportSnapshot):CoverageGroup[]{
 const usage=snapshot.result.extra?.knownUsage as {sourceUsage?:unknown;detailsTruncated?:boolean}|undefined;
 const groups=new Map<string,{group:CoverageGroup;rows:CoveragePeriod[];seen:Set<string>}>();
 const asOf=Math.min(Date.parse(snapshot.result.asOf||snapshot.request.asOf||snapshot.generatedAt),Date.parse(snapshot.result.to));
 for(const row of maps(usage?.sourceUsage)){
  const from=string(row.from),to=string(row.to);if(!Number.isFinite(Date.parse(from))||!Number.isFinite(Date.parse(to))||Date.parse(to)<=Date.parse(from))continue;
  const nodeId=string(row.nodeId),pointId=string(row.pointId),unit=string(row.unit),key=JSON.stringify([nodeId,pointId,unit]);
  let entry=groups.get(key);
  if(!entry){
   const sourceIds=Array.isArray(row.sourceIds)?row.sourceIds.filter((id):id is string=>typeof id==='string'):[pointId];
   const source=sourceIds.map(id=>snapshot.display?.sources[id]).filter(Boolean).join(' / ')||snapshot.display?.sources[pointId]||'';
   const group:CoverageGroup={key,nodeId,pointId,unit,name:snapshot.display?.objects[nodeId]||snapshot.result.series.find(s=>s.nodeId===nodeId)?.name||'',source,periods:[],coveredSeconds:0,intervalCount:0,intervals:[],detailsTruncated:false,overlapping:false};
   entry={group,rows:[],seen:new Set()};groups.set(key,entry);
  }
  const rowKey=JSON.stringify([from,to,row.knownValue,row.knownValueType,row.knownQuality,row.coveredSeconds,row.intervalCount]);if(entry.seen.has(rowKey))continue;entry.seen.add(rowKey);
  const intervals=maps(row.intervals).map(r=>({intervalStart:string(r.intervalStart),intervalEnd:string(r.intervalEnd),value:number(r.value),valueType:string(r.valueType),quality:string(r.quality)}));
  entry.rows.push({key:rowKey,from,to,value:number(row.knownValue),valueType:string(row.knownValueType),quality:string(row.knownQuality),status:status(row,from,to,asOf),coveredSeconds:count(row.coveredSeconds),intervalCount:count(row.intervalCount),intervals,detailsTruncated:row.detailsTruncated===true,slots:1});
  const first=string(row.intervalStart),last=string(row.intervalEnd);
  if(number(row.knownValue)!==null){
   if(first&&(!entry.group.firstReading||Date.parse(first)<Date.parse(entry.group.firstReading)))entry.group.firstReading=first;
   if(last&&(!entry.group.lastReading||Date.parse(last)>Date.parse(entry.group.lastReading)))entry.group.lastReading=last;
  }
 }
 for(const {group,rows} of groups.values()){
  rows.sort((a,b)=>Date.parse(a.from)-Date.parse(b.from)||Date.parse(a.to)-Date.parse(b.to));
  let end=-Infinity;
  for(const row of rows){
   if(Date.parse(row.from)<end)group.overlapping=true;end=Math.max(end,Date.parse(row.to));
   group.coveredSeconds!+=row.coveredSeconds;group.intervalCount!+=row.intervalCount;group.detailsTruncated||=row.detailsTruncated;group.intervals.push(...row.intervals);
   const previous=group.periods.at(-1);
   if(previous&&Date.parse(previous.to)===Date.parse(row.from)&&previous.status===row.status&&previous.quality===row.quality){
    previous.to=row.to;previous.slots++;previous.coveredSeconds+=row.coveredSeconds;previous.intervalCount+=row.intervalCount;previous.detailsTruncated||=row.detailsTruncated;
    if(row.value!==null)previous.value=(previous.value??0)+row.value;previous.intervals.push(...row.intervals);
   }else group.periods.push({...row,intervals:[...row.intervals]});
  }
  group.intervals=uniqueIntervals(group.intervals);group.periods.forEach(p=>{p.intervals=uniqueIntervals(p.intervals);});
  if(group.overlapping){group.coveredSeconds=null;group.intervalCount=null;}
 }
 return [...groups.values()].map(e=>e.group);
}
