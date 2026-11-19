import type {Catalog,ReportRequest} from './types';
import type {CockpitSnapshot} from './cockpitTypes';
import {locale,t} from './i18n';
export interface CockpitConfigBase {id?:string;mod?:string;name:string;type?:'budget'|'rule';canWrite?:boolean;scopeKind:'project'|'space';scopeRef:string;categoryRef:string;enabled:boolean;version?:number;createdAt?:string;updatedAt?:string;effectiveAt?:string;actor?:string;validation?:'invalid';reasonCodes?:string[]}
export interface BudgetConfig extends CockpitConfigBase {month:string;currency:string;amount:number|null;distribution:'uniform'|'daily';dailyAmounts?:number[]}
export interface RuleConfig extends CockpitConfigBase {ruleType:'nonWorkingHighUsage'|'budgetVariance';calendarRef?:string;threshold:number|null;thresholdUnit:string;currency?:string}
export interface CockpitConfigList<T> {records:T[];complete:boolean;canWrite:boolean;projectRef:string}
export interface CockpitConfigAudit {targetId:string;records:{id:string;version:number;action:'create'|'update'|'delete';actor:string;at:string;before:Record<string,unknown>;after:Record<string,unknown>}[]}
export interface CockpitBudgetReferenceBasis {actualCost?:number;valueBasis:string;quality:string;reasonCodes?:string[];from:string;effectiveTo:string;asOf:string;currency?:string;method?:string}
export interface CockpitBudget {referenceVariancePct?:number|null;referenceMonthUsagePct?:number|null;referenceBasis?:CockpitBudgetReferenceBasis|null;status:string;budgetStatus?:'ok'|'unavailable';comparisonStatus?:'ok'|'unavailable';reasonCodes:string[];monthBudget:number|null;periodBudget:number|null;periodActualCost:number|null;deviationAmount:number|null;variancePct:number|null;monthUsagePct:number|null;calendarProgressPct:number|null;currency?:string;currencyBasis?:string;viewAccountingQuality?:string|null;costQuality?:string;costValueBasis?:string;costBoundaryBasis?:string;costReportRef?:string;costInputs?:{request:Record<string,unknown>;meterIds:string[];sourcePointIds:string[];sourceIds:string[];valueBasis:string;coverage:Record<string,unknown>[]};scopeRef?:string;scopeKind?:string;categoryRef?:string;from?:string;to?:string;asOf?:string;effectiveTo?:string;timeZone?:string;months:{month:string;status:string;amount:number|null;periodAmount:number|null;configRef?:string;version?:number;mod?:string;distribution?:string}[];curve:{ts:string;periodBudget:number;cumulativeBudget:number;month?:string;dayBudget?:number;actualDaySeconds?:number;from?:string;to?:string}[];configRefs?:{id:string;mod?:string;version?:number}[];configuration?:BudgetConfig[];formulas?:Record<string,string>;tariffSnapshot?:Record<string,unknown>[];currencySources?:Record<string,unknown>[]}
export interface RuleEvaluation {id:string;ruleType:RuleConfig['ruleType'];status:string;reasonCodes:string[];configuration:RuleConfig;profileRef:{id:string;version:number;mod:string};inputs:Record<string,unknown>;formula?:string;threshold:number|null;thresholdUnit:string;actual?:number|null;unit?:string;sourceIds?:string[];calendar?:Record<string,unknown>;from:string;to:string;asOf:string;triggerFrom?:string;triggerTo?:string}
export const configNumber=(value:number|null|undefined,digits=2)=>value==null||!Number.isFinite(value)?'—':new Intl.NumberFormat(locale,{maximumFractionDigits:digits}).format(value);
export const configSpaces=(catalog:Catalog)=>catalog.records.filter(row=>row.kind==='space'&&['site','floor'].includes(String(row.nativeSourceKind))&&!row.nativeHidden).map(row=>({id:String(row.nativeSourceId||row.id),name:row.name}));
export function monthDayCount(month:string){if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(month))return 0;const [year,m]=month.split('-').map(Number);return new Date(Date.UTC(year,m,0)).getUTCDate();}
export function configPayload(config:BudgetConfig|RuleConfig,type:'budget'|'rule'){
 const fields=['id','mod','name','scopeKind','scopeRef','categoryRef','enabled',...(type==='budget'?['month','currency','amount','distribution',...((config as BudgetConfig).distribution==='daily'?['dailyAmounts']:[])]:['ruleType','threshold','thresholdUnit',...((config as RuleConfig).ruleType==='nonWorkingHighUsage'?['calendarRef']:['currency'])])];
 const source=config as unknown as Record<string,unknown>;return Object.fromEntries(fields.filter(key=>source[key]!==undefined).map(key=>[key,source[key]]));
}
export function configValidation(config:BudgetConfig|RuleConfig,type:'budget'|'rule'){
 if(!config.name.trim()||config.name.length>160||!config.scopeRef||!config.categoryRef)return t('请填写名称、原生范围和能源分类。');
 if(type==='budget'){const b=config as BudgetConfig;if(!monthDayCount(b.month))return t('请选择有效的预算月份。');if(!/^[A-Z]{3}$/.test(b.currency))return t('币种须为三个大写字母，例如 CNY。');if(b.amount==null||!Number.isFinite(b.amount)||b.amount<=0)return t('月预算必须大于零。');
  if(b.distribution==='daily'){if(b.dailyAmounts?.length!==monthDayCount(b.month)||b.dailyAmounts.some(value=>!Number.isFinite(value)||value<0))return t('请为当月每一天填写非负金额，真实零可以保留。');const sum=b.dailyAmounts.reduce((a,b)=>a+b,0);if(Math.abs(sum-b.amount)>Math.max(b.amount,1)*1e-9)return t('逐日合计 {0} 与月预算 {1} 不一致，差额 {2}。',configNumber(sum),configNumber(b.amount),configNumber(sum-b.amount));}
 }else{const r=config as RuleConfig;if(r.threshold==null||!Number.isFinite(r.threshold)||r.threshold<0)return t('请填写非负规则阈值，不自动采用默认值。');if(r.ruleType==='nonWorkingHighUsage'&&(!r.calendarRef||!r.thresholdUnit))return t('非工作时段规则需要明确的日历及兼容用量单位。');if(r.ruleType==='budgetVariance'&&(r.thresholdUnit!=='%'||!r.currency||!/^[A-Z]{3}$/.test(r.currency)))return t('预算偏差规则需要百分比阈值和有效币种。');}
}
export function budgetCostRequest(snapshot:CockpitSnapshot):ReportRequest|undefined{
 const b=snapshot.modules.kpis?.data?.budget,r=b?.costInputs?.request;if(!b?.costReportRef||!snapshot.reports[b.costReportRef]||!r||!Array.isArray(r.nodeIds))return;
 return {kind:'profile',nodeIds:r.nodeIds as string[],dimension:'metering',categoryId:Array.isArray(r.categoryIds)?String(r.categoryIds[0]):snapshot.context.focusCategoryId,from:String(r.from),to:String(r.to),asOf:String(r.asOf||snapshot.context.asOf),period:r.period as ReportRequest['period'],metric:'cost',perArea:false};
}
export function budgetCurveRows(snapshot:CockpitSnapshot){
 const b=snapshot.modules.kpis?.data?.budget;if(!b)return [];
 const report=b.costReportRef?snapshot.reports[b.costReportRef]:undefined,start=Date.parse(b.from||snapshot.context.time.from);
 // Walk closed buckets once: annual hourly reports must not be rescanned for every daily budget marker.
 const lines=(report?.series||[]).map(line=>({points:line.points.filter(p=>Date.parse(p.ts)>=start).map(p=>({point:p,end:Date.parse(p.bucketEnd||report!.to)})).sort((a,b)=>a.end-b.end),index:0,sum:0,valid:true}));
 return (b.curve||[]).map(point=>{const until=Date.parse(point.ts);let actual:number|null=0;
  if(until>start){if(!lines.length)actual=null;for(const line of lines){while(line.index<line.points.length&&line.points[line.index].end<=until){const p=line.points[line.index++].point,value=Object.hasOwn(p,'completeValue')?p.completeValue:p.value;line.valid&&=typeof value==='number'&&Number.isFinite(value)&&(p.completeValueType??p.valueType)!=='na'&&['ok','good','valid'].includes(p.completeQuality||p.quality);if(line.valid)line.sum+=value!;}
    if(!line.index||!line.valid)actual=null;else if(actual!==null)actual+=line.sum;}}
  return {...point,actualCost:actual};
 });
}
