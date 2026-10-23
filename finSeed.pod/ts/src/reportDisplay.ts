import {locale,t} from './i18n';
import dayjs from 'dayjs';
import {dimensionNames} from './types';
import type {FinPoint,ReportDisplay,ReportResult,ReportSnapshot,SeedRecord,Series} from './types';

export const reportLabels:Record<string,string>={forecastDays:t("预测天数"),trainingDays:t("训练天数"),forecastRolling:t("滚动训练截止日"),forecasts:t("预测摘要"),backtests:t("历史留出回测"),modelScores:t("候选模型回测"),forecastFrom:t("预测开始"),algorithm:t("算法版本"),phase:t("数据阶段"),model:t("模型"),status:t("状态"),predictedTotal:t("预测合计"),mae:t("回测 MAE"),wape:t("回测 WAPE (%)"),baselineMae:t("上周同期 MAE"),backtestDays:t("回测天数"),validDays:t("有效训练日"),coverage:t("历史完整率 (%)"),trainingEnd:t("训练截止（不含）"),simulated:t("包含模拟历史"),errorRange:t("每日误差参考半宽"),lower:t("预测参考下限"),upper:t("预测参考上限"),prediction:t("回测预测值"),absoluteError:t("绝对误差"),index:t("日序号"),origin:t("训练天数"),baselineId:t("基准对象"),comparisonBaselineId:t("基准对象"),comparisonBaselineName:t("基准名称"),referenceId:t("基准对象"),referenceName:t("基准名称"),percentageQuality:t("变化率质量"),key:t("序号"),id:t("对象"),name:t("对象"),node:t("对象"),nodeId:t("计量对象"),category:t("能源类型"),categoryId:t("能源类型"),utility:t("分项"),utilityId:t("分项"),ts:t("时间"),date:t("日期"),time:t("时间"),value:t("值"),energy:t("能耗"),cost:t("费用"),coal:t("标准煤"),co2:t("碳排放"),unit:t("单位"),quality:t("数据质量"),area:t("面积"),total:t("合计"),ratio:t("占比"),percentage:t("占比 (%)"),rank:t("排名"),sourceIds:t("源点"),current:t("本期"),previous:t("对比期"),change:t("变化"),baseline:t("基准"),actual:t("实际"),x:'X',y:'Y',cop:'COP',working:t("工作时段"),nonWorking:t("非工作时段"),slope:t("斜率"),intercept:t("截距"),r2:t("决定系数 R²"),details:t("范围内表计明细"),scopeId:t("统计范围"),counted:t("实际计入合计"),scopeTotals:t("范围总量"),normalizationArea:t("面积归一化分母"),dimension:t("分析维度"),spacePath:t("空间路径"),meterPath:t("计量路径"),organizationPath:t("组织路径"),parentMeterId:t("上级表计"),included:t("计入合计"),reference:t("对比期"),difference:t("差值"),submeter:t("分表合计"),branchId:t("分表"),leakBranches:t("分表逐期明细"),leakTotals:t("总分表平衡汇总"),nonworking:t("非工作时段"),workingPercentage:t("工作用能占比 (%)"),workingQuality:t("工作用能质量"),nonworkingQuality:t("非工作用能质量"),hour:t("小时"),samples:t("样本数"),aggregation:t("汇总口径"),n:t("有效样本数"),totals:t("区间汇总"),overview:t("概览汇总"),comparisons:t("同期比较"),grandTotals:t("跨能源总览"),fitLine:t("拟合曲线端点"),utilityShares:t("分项占比"),band:t("峰谷平时段"),loadBands:t("峰谷平区间总量（非日均）"),loadBandsAggregation:t("峰谷平汇总口径"),nodeIds:t("分析对象"),referenceIds:t("参考点"),from:t("开始时间"),to:t("结束时间"),period:t("汇总间隔"),metric:t("指标"),kind:t("报表类型"),perArea:t("按面积归一化")};
export function reportLabel(snapshot:ReportSnapshot,key:string){const objects=snapshot.request.kind==='comparison'&&!snapshot.request.otherFrom;return (objects?({current:t("对象用量"),reference:t("基准用量"),difference:t("差值（对象 − 基准）"),percentage:t("相对基准变化率 (%)")} as Record<string,string>)[key]:undefined)||reportLabels[key]||key;}
export const numberText=(value:number)=>new Intl.NumberFormat(locale,{maximumFractionDigits:2,useGrouping:false}).format(value);
export function displaySeriesName(series:Series):string{
 const suffix=series.role==='history'?' · 历史':series.role==='forecast'?' · 预测':'';
 return suffix&&series.name.endsWith(suffix)?series.name.slice(0,-suffix.length)+t(suffix):series.name;
}
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
 if(key==='sourceIds'||key==='sourceId')return snapshot.display?.sources[id]||t("源点名称不可用");
 const names=id.split('|').map(part=>snapshot.display?.objects[part]||snapshot.display?.sources[part]).filter(Boolean);
 return snapshot.display?.objects[id]||snapshot.display?.sources[id]||names.join(' / ')||(key==='categoryId'?t("能源类型名称不可用"):t("对象名称不可用"));
}
export function readableReportValue(snapshot:ReportSnapshot,key:string,value:unknown):unknown{
 if(value===null||value===undefined)return value;
 if(key==='unit'&&typeof value==='string')return t(value);
 if((key==='id'||key.endsWith('Id'))&&typeof value==='string')return referenceName(snapshot,value,key);
 if(key.endsWith('Ids')&&Array.isArray(value))return value.map(id=>referenceName(snapshot,String(id),key)).join('、');
 if(key==='model')return ({seasonalNaive:t("上周同期"),weekdayMean:t("近期同星期均值"),dampedTrend:t("周周期＋衰减趋势")} as Record<string,string>)[String(value)]||value;
 if(key==='phase')return value==='forecast'?t("预测"):t("历史");
 if(key==='simulated'||key==='forecastRolling')return value===true?t("是"):t("否");
 if(key==='quality'&&value==='predicted')return t("预测值");
 if(key==='dimension')return dimensionNames[value as keyof typeof dimensionNames]||value;
 if(Array.isArray(value))return value.map(item=>readableReportValue(snapshot,'',item));
 if(typeof value==='object')return Object.fromEntries(Object.entries(value).filter(([k])=>k!=='key').map(([k,v])=>[reportLabel(snapshot,k),readableReportValue(snapshot,k,v)]));
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
 if(period==='week')return t("{0}月{1}日当周",Number(ts.slice(5,7)),Number(ts.slice(8,10)));
 if(period==='year')return ts.slice(0,4)+(locale==='zh-CN'?'年':'');if(period==='month')return t("{0}年{1}月",ts.slice(0,4),Number(ts.slice(5,7)));
 if(period==='hour')return `${Number(ts.slice(5,7))}/${Number(ts.slice(8,10))} ${ts.slice(11,16)}`;
 return t("{0}月{1}日",Number(ts.slice(5,7)),Number(ts.slice(8,10)));
}
export function leakGroups(snapshot:ReportSnapshot){
 const {result}=snapshot;
 return result.series.map(series=>{const node=series.nodeId||series.id.split('|')[0];const matches=(row:Record<string,unknown>)=>(row.nodeId===node||!row.nodeId&&result.series.length===1)&&(!row.categoryId||row.categoryId===series.categoryId)&&(!row.unit||row.unit===series.unit);const branches=(Array.isArray(result.extra?.leakBranches)?result.extra.leakBranches:[]) as Record<string,unknown>[];const totals=(Array.isArray(result.extra?.leakTotals)?result.extra.leakTotals:[]) as Record<string,unknown>[];return {series,total:totals.find(matches),result:{...result,series:[series],rows:result.rows.filter(matches),extra:{...result.extra,leakBranches:branches.filter(matches)}}};});
}
export function profileGroups(snapshot:ReportSnapshot){
 const groups=new Map<string,{title:string;series:Series[]}>();
 for(const series of snapshot.result.series){const node=series.nodeId||series.id.split('|')[0];const reference=series.id.endsWith('|reference')||snapshot.request.referenceIds?.includes(node);const role=reference?t("参考曲线"):snapshot.result.kind==='primary'?t("折算对比"):t("用量对比");const kind=snapshot.display?.meterKinds[node];const category=series.categoryId?referenceName(snapshot,series.categoryId,'categoryId'):'';const key=`${series.categoryId||''}|${series.unit}|${role}`;const group=groups.get(key)||{title:[category,role,t(series.unit)].filter(Boolean).join(' · '),series:[]};group.series.push(!reference&&(kind==='totalMeter'||kind==='meter')?{...series,name:`${series.name}（${kind==='totalMeter'?t("总表"):t("分表")}）`}:series);groups.set(key,group);}
 return [...groups.values()];
}
export function profileStats(snapshot:ReportSnapshot,series:Series){
 const {from,to}=snapshot.result;const period=snapshot.request.period;const expectedTimes=new Set<number>();
 const start=period==='week'?dayjs(from).startOf('day').subtract((dayjs(from).day()+6)%7,'day'):dayjs(from).startOf(period);
 for(let at=start;at.valueOf()<Date.parse(to);at=at.add(1,period))expectedTimes.add(at.valueOf());
 const points=series.points.filter(point=>expectedTimes.has(Date.parse(point.ts))&&point.value!==null&&Number.isFinite(point.value)&&['ok','good','estimated','derived'].includes(point.quality));
 const valid=new Set(points.map(point=>Date.parse(point.ts))).size;const complete=valid===expectedTimes.size&&valid>0;
 const totals=(snapshot.result.summary.totals||[]) as {id:string;value:number|null}[];const total=totals.find(row=>row.id===series.id)?.value??null;
 const peakPoint=complete?points.reduce<typeof points[number]|undefined>((peak,point)=>!peak||point.value!>peak.value!?point:peak,undefined):undefined;
 return {total,average:complete&&total!==null?total/valid:null,peak:peakPoint?.value??null,peakAt:peakPoint?.ts,valid,expected:expectedTimes.size};
}
