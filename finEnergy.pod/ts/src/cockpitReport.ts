import type {CockpitSnapshot} from './cockpitTypes';
import type {ReportPoint,ReportSnapshot,ReportRequest,ReportKind} from './types';
import {applyKnownUsageDisplay} from './usageDisplay';
import {t} from './i18n';
export function cockpitCompleteValue(point:ReportPoint):number|'NA'|null {
 if((point.completeValueType??point.valueType)==='na')return 'NA';
 if(['filtered','substituted'].includes(point.completeQuality??point.quality))return null;
 return (Object.hasOwn(point,'completeValue')?point.completeValue:point.value)??null;
}
export function cockpitProfileSnapshot(snapshot:CockpitSnapshot):ReportSnapshot|undefined{
 const ref=snapshot.modules.trend?.data?.reportRef,raw=ref?snapshot.reports[ref]:undefined;if(!raw)return;
 const context=snapshot.context,result=structuredClone(raw);
 applyKnownUsageDisplay(result);
 return {project:context.project,title:t('用量趋势'),generatedAt:snapshot.generatedAt,request:{kind:'profile',nodeIds:context.reportScope.nodeIds,dimension:context.reportScope.dimension,spaceSource:'fin',from:context.time.from,to:context.time.to,asOf:context.asOf,period:context.time.period,metric:'energy',perArea:false,categoryId:context.focusCategoryId},result};
}
export function cockpitReferencedReport(snapshot:CockpitSnapshot,ref:string):ReportSnapshot|undefined{
 const refs=[snapshot.modules.time?.data?.dailyReportRef,snapshot.modules.time?.data?.workingReportRef,snapshot.modules.time?.data?.workingDaysReportRef,snapshot.modules.endUse?.data?.reportRef,snapshot.modules.organization?.data?.meterReportRef];if(!refs.includes(ref))return;
 const raw=snapshot.reports[ref];if(!raw)return;
 const context=snapshot.context,result=structuredClone(raw);
 applyKnownUsageDisplay(result);
 const labels:Partial<Record<ReportKind,string>>={daily:t('各小时平均用量'),utility:t('用途分布'),workingHours:t('工作时段用量'),workingDays:t('工作日用量'),profile:t('范围内表计用量')};
 return {project:context.project,title:labels[result.kind]||t('驾驶舱分析结果'),generatedAt:snapshot.generatedAt,request:{kind:result.kind,nodeIds:snapshot.boundary.meterIds,dimension:'metering',from:result.from,to:result.to,asOf:context.asOf,period:result.period as ReportRequest['period'],metric:'energy',perArea:false,categoryId:context.focusCategoryId},result};
}
export function cockpitOrganizationReport(snapshot:CockpitSnapshot):ReportSnapshot|undefined{
 const data=snapshot.modules.organization?.data;if(!data)return;
 const context=snapshot.context,rows=data.nodes.filter(node=>data.rootIds.includes(node.id)).map(node=>({...structuredClone(node),nodeId:node.id,name:node.nodeKind==='unassigned'?t('未指定组织'):node.name}));
 return {project:context.project,title:t('组织分布'),generatedAt:snapshot.generatedAt,request:{kind:'ranking',nodeIds:data.meterIds,dimension:'metering',from:context.time.from,to:context.time.to,asOf:context.asOf,period:context.time.period,metric:'energy',perArea:false,categoryId:context.focusCategoryId},result:{kind:'ranking',from:context.time.from,to:context.time.to,asOf:context.asOf,period:context.time.period,series:[],rows,summary:{},warnings:[]}};
}
