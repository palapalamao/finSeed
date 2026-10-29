import {isReferenceCurve,referenceAxes,referenceLine} from './referenceCurves';
import {qualityLabel} from './reportQuality';
import {t} from './i18n';
import dayjs,{type Dayjs} from 'dayjs';
import type {EChartsCoreOption} from 'echarts/core';
import type {ReportRequest,ReportResult,EnerCubixRecord} from './types';
import {compactReportTime,numberText} from './reportDisplay';

export type ComparisonPreset='monthToDate'|'previousMonth'|'last7Days'|'months'|'custom';
export interface ComparisonSelection {range:[Dayjs,Dayjs];otherRange:[Dayjs,Dayjs];alignment?:'duration'|'calendarMonth';preset:ComparisonPreset;notice?:string}
export function comparisonTemplateObjects(request:ReportRequest,records:EnerCubixRecord[]){
 const nodeIds=[...request.nodeIds],referenceIds:string[]=[];
 for(const id of request.referenceIds||[]){const object=records.find(record=>record.id===id&&['group','space','organization','meter','totalMeter','sensor'].includes(record.kind));if(object?.id)nodeIds.push(object.id);else referenceIds.push(id);}
 return {nodeIds:[...new Set(nodeIds)],referenceIds:[...new Set(referenceIds)]};
}
export function alignComparison(range:[Dayjs,Dayjs],otherStart:Dayjs):ComparisonSelection{
 return {range,otherRange:[otherStart,otherStart.add(range[1].diff(range[0]),'millisecond')],alignment:'duration',preset:'custom'};
}
export function comparisonPreset(preset:Exclude<ComparisonPreset,'custom'>,now=dayjs()):ComparisonSelection{
 const month=now.startOf('month'),previous=month.subtract(1,'month');
 if(preset==='months')return {range:[month,month.add(1,'month')],otherRange:[previous,month],alignment:'calendarMonth',preset};
 if(preset==='last7Days'){const end=now.startOf('day').add(1,'day'),start=end.subtract(7,'day');return {...alignComparison([start,end],start.subtract(7,'day')),preset};}
 const start=preset==='previousMonth'?previous:month,other=start.subtract(1,'month');
 const requested=preset==='previousMonth'?start.daysInMonth():now.date(),days=Math.min(requested,other.daysInMonth());
 return {range:[start,start.add(days,'day')],otherRange:[other,other.add(days,'day')],alignment:'duration',preset,...(days<requested?{notice:t("对比月只有 {0} 天，两期均取前 {1} 天；查看完整月份可选择整月对比。",other.daysInMonth(),days)}:{})};
}
export function resolveComparison(value:ComparisonSelection):ComparisonSelection{return value.preset==='custom'?value:comparisonPreset(value.preset);}
export function comparisonFromRequest(request:ReportRequest):ComparisonSelection{
 if(request.comparisonPreset&&request.comparisonPreset!=='custom')return comparisonPreset(request.comparisonPreset);
 return {range:[dayjs(request.from),dayjs(request.to)],otherRange:[dayjs(request.otherFrom),dayjs(request.otherTo)],alignment:request.comparisonAlignment,preset:'custom',...(!request.comparisonAlignment?{notice:t("旧模板保留原查询区间。重新选择日期后，两期按等长对齐。")}:{})};
}
export function comparisonRangeText(range:[Dayjs,Dayjs]){return t("{0} — {1}（{2} 天）",range[0].format('YYYY-MM-DD'),range[1].subtract(1,'millisecond').format('YYYY-MM-DD'),numberText(range[1].diff(range[0],'day',true)));}
export function comparisonSlots(from:string,to:string,period:string,alignment?:string):string[]{
 const start=dayjs(from),end=dayjs(to);if(!start.isValid()||!end.isValid())return [];
 const aligned=alignment==='duration'&&['hour','day','week'].includes(period);
 let at=aligned?start:period==='week'?start.startOf('day').subtract((start.day()+6)%7,'day'):start.startOf(period as 'day');
 const output:string[]=[];while(at.valueOf()<end.valueOf()&&output.length<100001){output.push(at.format('YYYY-MM-DDTHH:mm:ssZ'));at=aligned?at.add(period==='hour'?3600000:period==='day'?86400000:604800000,'millisecond'):at.add(1,period as 'day');}
 return output;
}
export function comparisonChartOptions(result:ReportResult,request:ReportRequest,colors=['#1576a7','#29a28b','#dc9f36','#757cbb','#60b3c3','#cb7662']):EChartsCoreOption{
 const paired=!!request.otherFrom&&!!request.otherTo;
 const times=comparisonSlots(result.from,result.to,result.period,request.comparisonAlignment);
 const otherTimes=paired?comparisonSlots(request.otherFrom!,request.otherTo!,result.period,request.comparisonAlignment):[];
 const business=result.series.filter(series=>!isReferenceCurve(series,'comparison')),references=result.series.filter(series=>isReferenceCurve(series,'comparison'));
 const referenceUnits=[...new Set(references.map(series=>series.unit))];
 const length=Math.max(times.length,otherTimes.length),units=Array.from(new Set(business.map(series=>series.unit)));
 const primary=business.filter(series=>!paired||!series.id.endsWith('|reference'));
 const baselineId=String(result.extra?.comparisonBaselineId||request.baselineId||'');
 const bars=primary.flatMap((series,index)=>{
  const pair=paired?business.find(reference=>reference.id===series.id+'|reference'):undefined;
  return [series,...(paired?[pair]:[])].map((line,side)=>{
   const slots=side?otherTimes:times,points=new Map(line?.points.map(point=>[Date.parse(point.ts),point]));
   return {name:`${series.name}${paired?side?t(" · 对比期"):t(" · 本期"):baselineId&&(series.nodeId||series.id.split('|')[0])===baselineId?t("（基准）"):''}`,type:'bar',barMaxWidth:36,yAxisIndex:units.indexOf(series.unit),itemStyle:{color:colors[index%colors.length],opacity:side ? 0.45 : 1},emphasis:{focus:'series'},data:Array.from({length},(_,i)=>{const ts=slots[i],point=ts?points.get(Date.parse(ts)):undefined;return {value:point?.value??null,ts:point?.ts||ts||t("此期无对应时段"),quality:point?.quality||'missing',unit:t(series.unit)};})};
  });
 });
 return {animation:false,tooltip:{trigger:'axis',axisPointer:{type:'shadow'},renderMode:'richText',formatter:(items:unknown)=>{
  const values=items as {seriesName:string;data:{value:number|null;ts:string;quality:string;unit:string;coverage?:string}}[];
  return values.map(({seriesName,data})=>`${seriesName}\n${data.ts.replace('T',' ')}  ${data.value===null?data.quality==='na'?'NA':t("缺测"):numberText(data.value)+' '+data.unit} · ${qualityLabel(data.quality)}${data.coverage?'\n'+data.coverage:''}`).join('\n\n');
 }},legend:{type:'scroll',bottom:2},grid:{left:70,right:35+Math.max(0,units.length+referenceUnits.length-1)*45,top:35,bottom:100},xAxis:{type:'category',data:Array.from({length},(_,i)=>paired?`${times[i]?compactReportTime(times[i],result.period):t("无对应时段")}\n${otherTimes[i]?compactReportTime(otherTimes[i],result.period):t("无对应时段")}`:compactReportTime(times[i],result.period)),axisLabel:{hideOverlap:true}},yAxis:[...units.map((unit,index)=>({type:'value',name:t(unit),scale:false,position:index?'right':'left',offset:Math.max(0,index-1)*45})),...referenceAxes(referenceUnits,Math.max(0,units.length-1))],dataZoom:[{type:'inside'},{type:'slider',bottom:35,height:18}],series:[...bars,...references.map((series,index)=>{const slots=series.referencePeriod==='comparison'?otherTimes:times;const line=referenceLine(series,slots,units.length+referenceUnits.indexOf(series.unit),colors[(primary.length+Math.floor(index/2))%colors.length],true);return {...line,data:Array.from({length},(_,i)=>line.data[i]||{value:null,ts:t("此期无对应时段"),quality:'missing',unit:t(series.unit),reference:true,coverage:''})};})]};
}
