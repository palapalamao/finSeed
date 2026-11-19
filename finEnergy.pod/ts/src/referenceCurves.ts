import {t} from './i18n';
import type {ReportKind,ReportPoint,Series} from './types';

export const referenceKinds:ReportKind[]=['profile','daily','utility','primary','leak','comparison'];
// Legacy suffixes apply only outside comparisons, whose energy baseline already
// uses |reference. New frozen reports always carry an explicit series role.
export function isReferenceCurve(series:Series,kind?:ReportKind,ids:readonly string[]=[]){
 return series.role==='reference'||kind!=='comparison'&&(series.id.endsWith('|reference')||ids.includes(series.nodeId||series.id.split('|')[0]));
}
export function referenceName(series:Series,paired=false){
 return paired?t(series.referencePeriod==='comparison'?'{0} · 对比期参考':'{0} · 本期参考',series.name):t('{0} · 参考',series.name);
}
export function referenceCoverage(point:Partial<ReportPoint>){
 return point.expectedSamples===undefined?'':t('有效小时 {0}/{1}；缺测 {2}；NA {3}',point.validSamples??0,point.expectedSamples,point.missingSamples??0,point.naSamples??0);
}
export function referenceLine(series:Series,times:string[],axis:number,color:string,paired=false){
 const points=new Map(series.points.map(point=>[Date.parse(point.ts),point]));
 return {name:`${referenceName(series,paired)}${series.unit?` (${t(series.unit)})`:''}`,type:'line',yAxisIndex:axis,z:3,connectNulls:false,showSymbol:times.length<=48,itemStyle:{color},lineStyle:{color,type:series.referencePeriod==='comparison'?'dashed':'solid'},data:times.map(ts=>{const point=points.get(Date.parse(ts));return {value:point?.value??null,ts:point?.ts||ts,quality:point?.quality||'missing',unit:t(series.unit),reference:true,coverage:referenceCoverage(point||{})};})};
}
export function referenceAxes(units:string[],offset=0){return units.map((unit,index)=>({type:'value',name:t(unit),scale:true,position:'right',offset:(index+offset)*45}));}
