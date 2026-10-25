import dayjs from 'dayjs';
import type {EChartsOption} from 'echarts';
import type {CleaningPreview} from './cleaning';
import {cleaningReason} from './cleaning';
import {t} from './i18n';

type Reading=CleaningPreview['raw'][number];
const numeric=(value:unknown):value is number=>typeof value==='number'&&Number.isFinite(value);
const timestamp=(value:unknown)=>typeof value==='string'?Date.parse(value):NaN;
export function cleaningChartData(preview:CleaningPreview){
 const points=(rows:Reading[])=>rows.filter(row=>Number.isFinite(timestamp(row.ts))).map(reading=>({value:[timestamp(reading.ts),reading.valueType==='na'||!numeric(reading.value)?null:reading.value] as [number,number|null],reading})).sort((a,b)=>a.value[0]-b.value[0]);
 const raw=points(preview.raw),cleaned=points(preview.cleaned);
 const anomalies=preview.details.flatMap(detail=>{
  const reason=String(detail.reason||detail.rule||'');const start=timestamp(detail.intervalStart||detail.ts),end=timestamp(detail.intervalEnd);
  if(!reason||['ok','noPrevious','removedNA'].includes(reason)||!Number.isFinite(start))return [];
  const source=!!preview.pointId&&typeof detail.pointId==='string'&&detail.pointId!==preview.pointId;
  return [{start,end:Number.isFinite(end)&&end>=start?end:start,reason,corrected:reason==='rollover',rawValue:!source&&numeric(detail.rawValue)?detail.rawValue:null,detail}];
 }).sort((a,b)=>a.start-b.start);
 const times=[timestamp(preview.from),timestamp(preview.to),...raw.map(row=>row.value[0]),...cleaned.map(row=>row.value[0])].filter(Number.isFinite);
 const min=times.reduce((a,b)=>Math.min(a,b),Infinity),max=times.reduce((a,b)=>Math.max(a,b),-Infinity);
 return {raw,cleaned,anomalies,min:Number.isFinite(min)?min:0,max:Number.isFinite(max)?Math.max(max,min+1):1,hasValues:[...raw,...cleaned].some(row=>row.value[1]!==null)};
}
export type CleaningChartData=ReturnType<typeof cleaningChartData>;
export function cleaningZoomRange(data:CleaningChartData,index:number){
 const anomaly=data.anomalies[index];if(!anomaly)return;
 const padding=Math.max((anomaly.end-anomaly.start)*2,60000);
 return {startValue:Math.max(data.min,anomaly.start-padding),endValue:Math.min(data.max,anomaly.end+padding)};
}
export function cleaningChartOption(data:CleaningChartData,unit:string):EChartsOption{
 const rawName=t('原始读数'),cleanName=t('清洗后用量'),anomalyName=t('异常与修正');
 const areas=data.anomalies.filter(row=>row.end>row.start).map((row):[{xAxis:number;itemStyle:{color:string}},{xAxis:number}]=>[{xAxis:row.start,itemStyle:{color:row.corrected?'rgba(182,132,44,0.13)':'rgba(199,75,63,0.12)'}},{xAxis:row.end}]);
 const times=data.cleaned.map(row=>row.value[0]);
 const spacing=times.length>1?times.slice(1).reduce((gap,ts,index)=>ts>times[index]?Math.min(gap,ts-times[index]):gap,data.max-data.min):(data.max-data.min)/10;
 const axis={type:'time' as const,min:data.min-spacing/2,max:data.max+spacing/2,axisLabel:{hideOverlap:true,formatter:(value:number)=>dayjs(value).format('MM-DD\nHH:mm:ss')},splitNumber:4};
 const yAxis=(gridIndex:number)=>({type:'value' as const,gridIndex,scale:gridIndex===0,splitNumber:3,axisLine:{show:true,lineStyle:{color:'#738592'}},axisTick:{show:true},axisLabel:{show:true,color:'#435967',hideOverlap:true},splitLine:{lineStyle:{color:'#e9eff1'}}});
 const line=(name:string,index:number,color:string,rows:typeof data.raw)=>({name,type:'line' as const,xAxisIndex:index,yAxisIndex:index,data:rows,connectNulls:false,showSymbol:true,symbolSize:3,lineStyle:{width:1.5},itemStyle:{color},markArea:{silent:true,data:areas}});
 return {
  animation:false,color:['#3976ba','#137f7a','#c74b3f'],
  title:[{text:rawName,subtext:unit,left:10,top:4,textStyle:{fontSize:13,color:'#2e4554'},subtextStyle:{fontSize:11}},{text:cleanName,subtext:unit,left:10,top:'46%',textStyle:{fontSize:13,color:'#2e4554'},subtextStyle:{fontSize:11}}],
  grid:[{left:12,right:22,top:65,height:'25%',outerBoundsMode:'same'},{left:12,right:22,top:'58%',height:'25%',outerBoundsMode:'same'}],
  xAxis:[{...axis,gridIndex:0},{...axis,gridIndex:1}],yAxis:[yAxis(0),yAxis(1)],
  axisPointer:{link:[{xAxisIndex:[0,1]}]},
  dataZoom:[{type:'inside',xAxisIndex:[0,1],filterMode:'filter'},{type:'slider',xAxisIndex:[0,1],filterMode:'filter',bottom:4,height:20,labelFormatter:(value:number)=>dayjs(value).format('MM-DD HH:mm:ss')}],
  tooltip:{trigger:'axis',renderMode:'richText',confine:true,formatter:params=>{
   const entries=Array.isArray(params)?params:[params];
   return entries.map(entry=>{
    const item=entry.data as {reading?:Reading;anomaly?:CleaningChartData['anomalies'][number]};
    if(item?.anomaly){const a=item.anomaly;return [cleaningReason(a.reason),a.detail.pointId?t('来源：{0}',a.detail.pointId):'',t('{0} 至 {1}',String(a.detail.intervalStart||a.detail.ts),String(a.detail.intervalEnd||a.detail.ts))].filter(Boolean).join('\n');}
    const row=item?.reading;if(!row)return '';
    const value=row.valueType==='na'?'NA':row.value===null?t('空值'):String(row.value);
    return `${row.ts}\n${t('{0}：{1}',entry.seriesName||'',value)}${numeric(row.value)&&row.valueType!=='na'&&unit?' '+unit:''}`;
   }).filter(Boolean).join('\n');
  }},
  series:[line(rawName,0,'#3976ba',data.raw),{name:cleanName,type:'bar',xAxisIndex:1,yAxisIndex:1,data:data.cleaned,barMaxWidth:30,itemStyle:{color:'#137f7a'},markArea:{silent:true,data:areas}},{name:anomalyName,type:'scatter',xAxisIndex:0,yAxisIndex:0,symbol:'diamond',symbolSize:10,itemStyle:{color:'#c74b3f'},z:5,data:data.anomalies.filter(row=>row.rawValue!==null).map(anomaly=>({value:[anomaly.end,anomaly.rawValue],anomaly,itemStyle:{color:anomaly.corrected?'#b6842c':'#c74b3f'}}))}]
 };
}
