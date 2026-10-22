import dayjs from 'dayjs';
import {dimensionNames} from './types';
import type {FinPoint,ReportDisplay,ReportResult,ReportSnapshot,SeedRecord,Series} from './types';

export const reportLabels:Record<string,string>={key:'序号',id:'对象',name:'对象',node:'对象',nodeId:'计量对象',category:'能源类型',categoryId:'能源类型',utility:'分项',utilityId:'分项',ts:'时间',date:'日期',time:'时间',value:'值',energy:'能耗',cost:'费用',coal:'标准煤',co2:'碳排放',unit:'单位',quality:'数据质量',area:'面积',total:'合计',ratio:'占比',percentage:'占比 (%)',rank:'排名',sourceIds:'源点',current:'本期',previous:'对比期',change:'变化',baseline:'基准',actual:'实际',x:'X',y:'Y',cop:'COP',working:'工作时段',nonWorking:'非工作时段',slope:'斜率',intercept:'截距',r2:'决定系数 R²',details:'范围内表计明细',scopeId:'统计范围',counted:'实际计入合计',scopeTotals:'范围总量',normalizationArea:'面积归一化分母',dimension:'分析维度',spacePath:'空间路径',meterPath:'计量路径',organizationPath:'组织路径',parentMeterId:'上级表计',included:'计入合计',reference:'对比期',difference:'差值',submeter:'分表合计',nonworking:'非工作时段',workingPercentage:'工作用能占比 (%)',workingQuality:'工作用能质量',nonworkingQuality:'非工作用能质量',hour:'小时',samples:'样本数',aggregation:'汇总口径',n:'有效样本数',totals:'区间汇总',overview:'概览汇总',comparisons:'同期比较',grandTotals:'跨能源总览',fitLine:'拟合曲线端点',utilityShares:'分项占比',band:'峰谷平时段',loadBands:'峰谷平区间总量（非日均）',loadBandsAggregation:'峰谷平汇总口径',nodeIds:'分析对象',referenceIds:'参考点',from:'开始时间',to:'结束时间',period:'汇总间隔',metric:'指标',kind:'报表类型',perArea:'按面积归一化'};
export const numberText=(value:number)=>new Intl.NumberFormat('zh-CN',{maximumFractionDigits:2,useGrouping:false}).format(value);
export function buildReportDisplay(records:SeedRecord[],points:FinPoint[]=[]):ReportDisplay{
 const objects:Record<string,string>={},sources:Record<string,string>={},meterKinds:Record<string,string>={};
 for(const r of records){if(r.id){objects[r.id]=r.name;meterKinds[r.id]=r.kind;}if(r.kind==='nativePoint'&&typeof r.nativeSourceId==='string'&&typeof r.nativeDis==='string')sources[r.nativeSourceId]=r.nativeDis;}
 for(const point of points)sources[point.id]=point.name;
 return {objects,sources,meterKinds};
}
export function reportSourceIds(result:ReportResult):string[]{
 const ids=new Set<string>();const visit=(value:unknown,key='')=>{if(key==='sourceIds'&&Array.isArray(value)){value.forEach(id=>{if(typeof id==='string')ids.add(id);});}else if(Array.isArray(value))value.forEach(item=>visit(item));else if(value&&typeof value==='object')Object.entries(value).forEach(([k,v])=>visit(v,k));};visit(result);return [...ids];
}
export async function reportPointNames(result:ReportResult,records:SeedRecord[],find:(id:string)=>Promise<{items:FinPoint[]}>):Promise<FinPoint[]>{
 const known=buildReportDisplay(records).sources;const missing=reportSourceIds(result).filter(id=>!known[id]);const points:FinPoint[]=[];
 for(let offset=0;offset<missing.length;offset+=8)points.push(...(await Promise.all(missing.slice(offset,offset+8).map(async id=>{try{return (await find(id)).items.filter(point=>point.id===id);}catch{return [];}}))).flat());
 return points;
}
function referenceName(snapshot:ReportSnapshot,id:string,key:string):string{
 if(key==='sourceIds'||key==='sourceId')return snapshot.display?.sources[id]||'源点名称不可用';
 const names=id.split('|').map(part=>snapshot.display?.objects[part]||snapshot.display?.sources[part]).filter(Boolean);
 return snapshot.display?.objects[id]||snapshot.display?.sources[id]||names.join(' / ')||(key==='categoryId'?'能源类型名称不可用':'对象名称不可用');
}
export function readableReportValue(snapshot:ReportSnapshot,key:string,value:unknown):unknown{
 if(value===null||value===undefined)return value;
 if((key==='id'||key.endsWith('Id'))&&typeof value==='string')return referenceName(snapshot,value,key);
 if(key.endsWith('Ids')&&Array.isArray(value))return value.map(id=>referenceName(snapshot,String(id),key)).join('、');
 if(key==='dimension')return dimensionNames[value as keyof typeof dimensionNames]||value;
 if(Array.isArray(value))return value.map(item=>readableReportValue(snapshot,'',item));
 if(typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([k])=>k!=='key').map(([k,v])=>[reportLabels[k]||k,readableReportValue(snapshot,k,v)]));
 return value;
}
export function reportCellText(snapshot:ReportSnapshot,key:string,value:unknown,precise=false):string{
 const readable=readableReportValue(snapshot,key,value);
 if(readable===null||readable===undefined)return '—';
 if(typeof readable==='number')return precise?String(readable):numberText(readable);
 if(typeof readable==='object')return JSON.stringify(readable);
 return String(readable);
}
export function compactReportTime(ts:string,period:string):string{
 if(period==='year')return ts.slice(0,4)+'年';if(period==='month')return `${ts.slice(0,4)}年${Number(ts.slice(5,7))}月`;
 if(period==='hour')return `${Number(ts.slice(5,7))}/${Number(ts.slice(8,10))} ${ts.slice(11,16)}`;
 return `${Number(ts.slice(5,7))}月${Number(ts.slice(8,10))}日`;
}
export function profileGroups(snapshot:ReportSnapshot){
 const groups=new Map<string,{title:string;series:Series[]}>();
 for(const series of snapshot.result.series){const node=series.nodeId||series.id.split('|')[0];const reference=series.id.endsWith('|reference')||snapshot.request.referenceIds?.includes(node);const role=reference?'参考曲线':'用量对比';const kind=snapshot.display?.meterKinds[node];const category=series.categoryId?referenceName(snapshot,series.categoryId,'categoryId'):'';const key=`${series.categoryId||''}|${series.unit}|${role}`;const group=groups.get(key)||{title:[category,role,series.unit].filter(Boolean).join(' · '),series:[]};group.series.push(!reference&&(kind==='totalMeter'||kind==='meter')?{...series,name:`${series.name}（${kind==='totalMeter'?'总表':'分表'}）`}:series);groups.set(key,group);}
 return [...groups.values()];
}
export function profileStats(snapshot:ReportSnapshot,series:Series){
 const {from,to}=snapshot.result;const period=snapshot.request.period;const expectedTimes=new Set<number>();
 for(let at=dayjs(from).startOf(period);at.valueOf()<Date.parse(to);at=at.add(1,period))expectedTimes.add(at.valueOf());
 const points=series.points.filter(point=>expectedTimes.has(Date.parse(point.ts))&&point.value!==null&&Number.isFinite(point.value)&&['ok','good','estimated','derived'].includes(point.quality));
 const valid=new Set(points.map(point=>Date.parse(point.ts))).size;const complete=valid===expectedTimes.size&&valid>0;
 const totals=(snapshot.result.summary.totals||[]) as {id:string;value:number|null}[];const total=totals.find(row=>row.id===series.id)?.value??null;
 const peakPoint=complete?points.reduce<typeof points[number]|undefined>((peak,point)=>!peak||point.value!>peak.value!?point:peak,undefined):undefined;
 return {total,average:complete&&total!==null?total/valid:null,peak:peakPoint?.value??null,peakAt:peakPoint?.ts,valid,expected:expectedTimes.size};
}
