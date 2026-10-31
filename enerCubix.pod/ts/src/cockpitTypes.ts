import type {ReportResult} from './types';

export type CockpitFace='space'|'time'|'endUse'|'organization';
export const cockpitModules=['kpis','trend','time','endUse','organization'] as const;
export interface CockpitScope {dimension:'space'|'metering'|'organization';nodeIds:string[];selectionIntent:'range'|'explicitObjects'}
export interface CockpitAreaSource {id:string;name:string;area:number|null;source:'space'|'custom';nativeRef:string|null;mod:string|null;nativeArea:null|{nativeRef:string;mod:string|null;tag:'area';value:number|null;unit:string|null;areaM2:number|null}}
export interface CockpitAreaResolution {status:'ok'|'missingArea'|'ambiguousArea';areaM2:number|null;basis:'nativeSpace'|'custom'|'mixed'|'unknown';spaceRefs:string[];customBoundaryIds:string[];excludedOverlaps:{id:string;coveredBy:string;reasonCode:'containedSpace'|'duplicateServiceSpace'}[];energyBoundaryId:string;sourceRevisions:CockpitAreaSource[];reasonCodes:string[]}
export interface CockpitAreaFormula {version:1;expression:'energy / areaM2';energyBoundaryId:string;numerator:{value:number|null;completeValue:number|null;knownValue:number|null;valueBasis:CockpitMetric['valueBasis'];unit:string;sourceIds:string[]};denominator:{value:number|null;unit:'m²';sourceRevisions:CockpitAreaSource[]};value:number|null;unit:string}
export interface CockpitRequest {
 schemaVersion:1;requestId:string;reportScope:CockpitScope;focusCategoryId:string;auxiliaryCategoryId?:string;
 time:{preset:'today'|'thisMonth'|'thisYear'|'custom';period:'hour'|'day'|'month';from?:string;to?:string};
 asOf?:string;modules:(typeof cockpitModules)[number][];comparison?:{mode:'none'|'presetDefault'|'custom';from?:string;to?:string};
}
export interface CockpitMetric {
 id:string;categoryId?:string;value:number|null;valueType:'number'|'na'|'null';unit:string;quality:string;
 valueBasis:'complete'|'knownSubtotal'|'cleanedWithReplacement'|'unavailable'|'currentState';
 completeValue?:number|null;knownValue?:number|null;sourceIds:string[];reasonCodes?:string[];
 comparison?:{kind:string;currentRange:{from:string;to:string};referenceRange:{from:string;to:string};current:number|null;reference:number|null;comparable:boolean;difference:number|null;changeRate:number|null;reasonCodes:string[];durationDifferenceSeconds:number};
 details?:Record<string,unknown>&{areaResolution?:CockpitAreaResolution;formula?:CockpitAreaFormula};coverage?:Record<string,unknown>[];stateObservedAt?:string|null;
}
export interface CockpitConclusion {id:string;ruleId:string;ruleVersion:number;messageKey:string;args:Record<string,unknown>;evidenceRefs:string[];priority:number}
export interface CockpitHeatmapCell {seriesId:string;nodeId:string;date:string;hour:number;ts:string;value:number;unit:string;quality:string;sourceIds:string[]}
export interface CockpitTimeData {dailyReportRef:string;workingReportRef?:string;workingDaysReportRef?:string;heatmap:CockpitHeatmapCell[];excludedDays:{seriesId:string;date:string;reasonCode:string}[]}
export interface CockpitEndUseData {reportRef:string;additive:boolean;meterIds:string[]}
export interface CockpitDistributionNode {id:string;name:string;parentId:string|null;nodeKind:'organization'|'unassigned';meterIds:string[];unit:string;value:number|null;valueType:'number'|'null'|'na';completeValue:number|null;knownValue:number|null;valueBasis:CockpitMetric['valueBasis'];quality:string;sourceIds:string[]}
export interface CockpitOrganizationData {rootIds:string[];nodes:CockpitDistributionNode[];meterIds:string[];meterReportRef:string;additive:boolean}
export interface CockpitModule<T> {status:'ok'|'partial'|'empty'|'unavailable'|'error';data?:T;reasonCodes?:string[];error?:{code:string;message?:string}}
export interface CockpitSnapshot {
 schemaVersion:1;snapshotId:string;requestId:string;generatedAt:string;
 context:{project:string;projectTimeZone:string;reportScope:CockpitScope;focusCategoryId:string;auxiliaryCategoryId?:string|null;time:CockpitRequest['time']&{from:string;to:string};asOf:string;comparison?:CockpitRequest['comparison']};
 provenance:{configFingerprint:string;relationshipBasis:'currentConfiguration';historyBasis:'ownPrimaryPointRaw';historyObservedFrom:string;historyObservedTo:string;sourceLastObservedAt:string|null;configRefs:{id:string;mod?:string}[];historyPlan?:{from:string;to:string;pointIds:string[]}[];appliedCleaning?:{pointId:string;profileId:string;profileVersion:number;parameters:Record<string,unknown>}[];historyConfigObservedFrom?:string|null;historyConfigObservedTo?:string|null};
 boundary:{id:string;meterIds:string[];sourcePointIds:string[];aggregateAllowed:boolean;overlaps:unknown[];excluded:unknown[]};
 modules:{kpis?:CockpitModule<{values:CockpitMetric[];conclusions:CockpitConclusion[]}>;trend?:CockpitModule<{reportRef:string}>;time?:CockpitModule<CockpitTimeData>;endUse?:CockpitModule<CockpitEndUseData>;organization?:CockpitModule<CockpitOrganizationData>};
 reports:Record<string,ReportResult>;quality:Record<string,unknown>[];
 capabilities:{canRead:boolean;canManage:boolean;availableFaces:string[]};limitations:string[];
}
