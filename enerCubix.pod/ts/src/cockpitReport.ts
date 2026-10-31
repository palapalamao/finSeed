import type {CockpitSnapshot} from './cockpitTypes';
import type {ReportPoint,ReportSnapshot} from './types';
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
