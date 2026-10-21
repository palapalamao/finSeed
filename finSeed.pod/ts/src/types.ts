export type Kind = 'space'|'nativePoint'|'organization'|'group'|'meter'|'totalMeter'|'sensor'|'category'|'subcategory'|'utility'|'tariff'|'calendar'|'expression'|'cop'|'template'|'settings'|'binding'|'job'|'alarm';
export type Dimension = 'space'|'metering'|'organization'|'legacy';
export interface SeedRecord {id?: string;mod?:string;kind:Kind;name:string;[key:string]:unknown}
export interface Catalog {version:string;project:string;user:{name:string;canWrite:boolean};records:SeedRecord[];spaceSource?:'fin';nativeTreePath?:string;nativeTreeWarnings?:string[]}
export interface FinPoint {id:string;name:string;unit?:string;kind?:string;his:boolean;hisMode?:string;source?:string;siteId?:string;floorId?:string;equipId?:string;siteName?:string;navName?:string;energyTags?:string[];hisStart?:string;hisEnd?:string;hisStatus?:string;hisErr?:string;hisLastCollect?:string;curStatus?:string;equipName?:string;equipNavName?:string;floorName?:string}
export type ReportKind = 'profile'|'ranking'|'proportion'|'utility'|'daily'|'comparison'|'primary'|'cop'|'leak'|'workingHours'|'workingDays'|'regression'|'trend'|'dashboard';
export type Preset='thisWeek'|'lastWeek'|'thisMonth'|'lastMonth'|'thisYear'|'lastYear';
export type Metric='energy'|'cost'|'coal'|'co2'|'rawcoal'|'oil';
export interface ReportRequest {kind:ReportKind;nodeIds:string[];dimension?:Dimension;spaceSource?:'fin';from:string;to:string;period:'hour'|'day'|'month'|'year';metric:Metric;perArea:boolean;referenceIds?:string[];otherFrom?:string;otherTo?:string;xId?:string;yId?:string;workHours?:number[]}
export function reportDimension(kind:ReportKind,dimension:Dimension):Dimension{return kind==='cop'?'legacy':dimension;}
export interface ReportPoint {ts:string;value:number|null;quality:string;sourceIds:string[];band?:'peak'|'valley'|'flat'|'unknown'}
export interface Series {id:string;name:string;categoryId?:string;unit:string;points:ReportPoint[]}
export interface ReportResult {kind:ReportKind;from:string;to:string;period:string;series:Series[];rows:Record<string,unknown>[];warnings:string[];summary:Record<string,unknown>;extra?:Record<string,unknown>}
export interface ReportSnapshot {request:ReportRequest;result:ReportResult;generatedAt:string;title:string;project:string;categoryIds?:string[];categoryNames?:string[]}
export const nodeKinds:Kind[]=['group','meter','totalMeter','sensor'];
export const treeDimensions=['space','metering','organization'] as const;
export const dimensionNames:Record<Dimension,string>={space:'空间',metering:'计量',organization:'组织',legacy:'历史报表口径'};
export const names:Record<Kind,string>={space:'空间',nativePoint:'FIN 原点',organization:'组织',group:'分组',meter:'分表',totalMeter:'总表',sensor:'传感器',category:'能源类型',subcategory:'能源子类',utility:'用途',tariff:'费率',calendar:'日历',expression:'计算公式',cop:'COP 配置',template:'报表模板',settings:'系统设置',binding:'参考点',job:'计算任务',alarm:'报警'};
export const reportNames:Record<ReportKind,string>={dashboard:'能源概览',profile:'能耗概况',ranking:'能耗排名',proportion:'能耗占比',utility:'用能用途',daily:'日均负荷',comparison:'对比分析',primary:'一次能源分析',cop:'COP 分析',leak:'泄漏分析',workingHours:'工作时段分析',workingDays:'工作日分析',regression:'回归分析',trend:'多点趋势'};
export const metricNames:Record<Metric,string>={energy:'能耗',cost:'费用',coal:'标准煤',co2:'碳排放',rawcoal:'原煤',oil:'石油当量'};
