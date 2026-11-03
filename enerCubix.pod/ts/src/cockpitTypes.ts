import type {ReportResult} from './types';
import type {CockpitBudget,RuleEvaluation} from './cockpitConfig';

export type CockpitFace='space'|'time'|'endUse'|'organization'|'balance'|'efficiency';
export const cockpitModules=['kpis','space','trend','time','endUse','organization','balance','efficiency','issues'] as const;
export interface CockpitScope {dimension:'space'|'metering'|'organization';nodeIds:string[];selectionIntent:'range'|'explicitObjects'}
export interface CockpitAreaSource {id:string;name:string;area:number|null;source:'space'|'custom';nativeRef:string|null;mod:string|null;nativeArea:null|{nativeRef:string;mod:string|null;tag:'area';value:number|null;unit:string|null;areaM2:number|null}}
export interface CockpitAreaResolution {status:'ok'|'missingArea'|'ambiguousArea';areaM2:number|null;basis:'nativeSpace'|'custom'|'mixed'|'unknown';spaceRefs:string[];customBoundaryIds:string[];excludedOverlaps:{id:string;coveredBy:string;reasonCode:'containedSpace'|'duplicateServiceSpace'}[];energyBoundaryId:string;sourceRevisions:CockpitAreaSource[];reasonCodes:string[]}
export interface CockpitAreaFormula {version:1;expression:'energy / areaM2';energyBoundaryId:string;numerator:{value:number|null;completeValue:number|null;knownValue:number|null;valueBasis:CockpitMetric['valueBasis'];unit:string;sourceIds:string[]};denominator:{value:number|null;unit:'m²';sourceRevisions:CockpitAreaSource[]};value:number|null;unit:string}
export interface CockpitRequest {
 schemaVersion:1;requestId:string;reportScope:CockpitScope;focusCategoryId:string;auxiliaryCategoryId?:string;
 time:{preset:'today'|'thisMonth'|'thisYear'|'custom';period:'hour'|'day'|'month';from?:string;to?:string};
 asOf?:string;modules:(typeof cockpitModules)[number][];comparison?:{mode:'none'|'presetDefault'|'previousMonth'|'custom';from?:string;to?:string};
}
export interface CockpitMetric {
 id:string;categoryId?:string;currencyStatus?:'ok'|'unavailable';currencyBasis?:string;currencyReasonCodes?:string[];value:number|null;valueType:'number'|'na'|'null';unit:string;quality:string;
 valueBasis:'complete'|'knownSubtotal'|'cleanedWithReplacement'|'unavailable'|'currentState';
 completeValue?:number|null;knownValue?:number|null;sourceIds:string[];reasonCodes?:string[];
 comparison?:{kind:string;currentRange:{from:string;to:string};referenceRange:{from:string;to:string};current:number|null;reference:number|null;comparable:boolean;difference:number|null;changeRate:number|null;reasonCodes:string[];durationDifferenceSeconds:number};
 details?:Record<string,unknown>&{areaResolution?:CockpitAreaResolution;formula?:CockpitAreaFormula};coverage?:Record<string,unknown>[];stateObservedAt?:string|null;
}
export interface CockpitConclusion {id:string;ruleId:string;ruleVersion:number;messageKey:string;args:Record<string,unknown>;evidenceRefs:string[];priority:number}
export interface CockpitHeatmapCell {seriesId:string;nodeId:string;date:string;hour:number;ts:string;value:number;unit:string;quality:string;sourceIds:string[]}
export interface CockpitSpaceNode {id:string;nativeId:string;name?:string;path?:string;parentId?:string|null;nodeKind:'site'|'floor'|'equip'|'point';basis:'ownPrimary'|'scopeAggregate';meterIds:string[];sourceIds:string[];value:number|null;knownValue:number|null;completeValue:number|null;valueType:CockpitMetric['valueType'];valueBasis:CockpitMetric['valueBasis'];unit:string;quality?:string;coverage?:Record<string,unknown>[];reasonCodes:string[]}
export interface CockpitSpaceData {nodes:CockpitSpaceNode[];rootIds:string[]}
export interface CockpitTimeData {dailyReportRef:string;workingReportRef?:string;workingDaysReportRef?:string;heatmap:CockpitHeatmapCell[];excludedDays:{seriesId:string;date:string;reasonCode:string}[]}
export interface CockpitEndUseData {reportRef:string;additive:boolean;meterIds:string[]}
export interface CockpitDistributionNode {id:string;name:string;parentId:string|null;nodeKind:'organization'|'unassigned';meterIds:string[];unit:string;value:number|null;valueType:'number'|'null'|'na';completeValue:number|null;knownValue:number|null;valueBasis:CockpitMetric['valueBasis'];quality:string;sourceIds:string[]}
export interface CockpitOrganizationData {rootIds:string[];nodes:CockpitDistributionNode[];meterIds:string[];meterReportRef:string;additive:boolean}
export interface CockpitCopItem {configId:string;name:string;configRef:{id:string;mod:string|null};numerator:CockpitMetric;denominator:CockpitMetric;ratio:CockpitMetric;from:string;to:string;asOf:string;coverageIds:string[];reportRef:string;actualEfficiency?:number;baselineEfficiency?:number}
export interface CockpitIssue {id:string;type:'energyAlarm'|'ruleClue'|'dataQuality';objectId:string;name?:string;categoryId:string;unit:string;evidenceFrom:string|null;evidenceTo:string|null;active:boolean|null;acknowledged:boolean|null;recoveredAt?:string|null;stateObservedAt:string|null;sourceIds:string[];reasonCodes?:string[];metricId?:string;nativeAlarmId?:string;episodeId?:string;ackAt?:string;ackBy?:string;ackNote?:string;actual?:number|null;valueType?:CockpitMetric['valueType'];valueBasis?:CockpitMetric['valueBasis'];reference?:number|null;hourCount?:number;hours?:{ts:string;value:number|null;unit:string|null;limit:number|null;quality:string|null}[];ruleType?:RuleEvaluation['ruleType'];configuration?:RuleEvaluation['configuration'];profileRef?:RuleEvaluation['profileRef'];inputs?:RuleEvaluation['inputs'];formula?:string;threshold?:number;thresholdUnit?:string;status?:string;evidenceTarget?:{reportRef?:string;parentSnapshotId?:string;kind:'profile';request:{kind:'profile';dimension:CockpitScope['dimension'];nodeIds:string[];categoryIds:string[];from:string;to:string;asOf:string;period:'hour'|'day'|'month';metric:'energy'|'cost'}};nativeDetail?:{available:boolean;reasonCode:string}}
export interface CockpitIssuesData {ruleEvaluations?:RuleEvaluation[];stateObservedAt:string|null;items:CockpitIssue[];total:number;topIds:string[];activeEventCount:number|null;eventScope:{basis:'selectedObjectsAndEffectiveMeters';objectIds:string[];meterIds:string[];categoryId:string}}
export interface CockpitModule<T> {status:'ok'|'partial'|'empty'|'unavailable'|'error';data?:T;reasonCodes?:string[];error?:{code:string;message?:string}}
export interface CockpitDiagnosticEntry {id:string;kind:'coveragePeriods'|'sourceUsage'|'sourceIntervals'|'cleaningEvents';grain:'hour'|'sourceRead'|'sourceInterval'|'cleaningEvent';totalCount:number|null;returnedCount:number;truncated:boolean;reason:'complete'|'snapshotDiagnosticBudget'|'upstreamDiagnosticLimit'|'upstreamAndSnapshotLimit';objectIds:string[];sourceIds:string[];sourceIdsComplete:boolean;upstreamReason?:string;requestRange:{from:string;to:string;asOf:string};returnedRange:{from:string;to:string}|null;reportRefs:string[]}
export interface CockpitDiagnostics {schemaVersion:1;preparedEntryLimited?:boolean;rowBudget:number;returnedCount:number;returnedByKind?:Record<string,number>;truncated:boolean;entries:CockpitDiagnosticEntry[]}
export interface ReportDiagnosticContext {snapshotId:string;reportRefs:string[];metadata:CockpitDiagnostics}
export interface CockpitSnapshot {
 schemaVersion:1;snapshotId:string;requestId:string;generatedAt:string;
 context:{project:string;projectTimeZone:string;reportScope:CockpitScope;focusCategoryId:string;auxiliaryCategoryId?:string|null;time:CockpitRequest['time']&{from:string;to:string};asOf:string;comparison?:CockpitRequest['comparison']};
 provenance:{configFingerprint:string;relationshipBasis:'currentConfiguration';historyBasis:'ownPrimaryPointRaw';historyObservedFrom:string;historyObservedTo:string;sourceLastObservedAt:string|null;configRefs:{id:string;mod?:string}[];historyPlan?:{from:string;to:string;pointIds:string[]}[];appliedCleaning?:{pointId:string;profileId:string;profileVersion:number;parameters:Record<string,unknown>}[];historyConfigObservedFrom?:string|null;historyConfigObservedTo?:string|null};
 boundary:{id:string;meterIds:string[];sourcePointIds:string[];aggregateAllowed:boolean;overlaps:unknown[];excluded:unknown[]};
 modules:{space?:CockpitModule<CockpitSpaceData>;kpis?:CockpitModule<{values:CockpitMetric[];conclusions:CockpitConclusion[];budget?:CockpitBudget}>;trend?:CockpitModule<{reportRef:string}>;time?:CockpitModule<CockpitTimeData>;endUse?:CockpitModule<CockpitEndUseData>;organization?:CockpitModule<CockpitOrganizationData>;balance?:CockpitModule<{reportRef:string;graphIds:string[]}>;efficiency?:CockpitModule<{items:CockpitCopItem[]}>;issues?:CockpitModule<CockpitIssuesData>};
 diagnostics?:CockpitDiagnostics;
 reports:Record<string,ReportResult>;quality:Record<string,unknown>[];
 capabilities:{canRead:boolean;canManage:boolean;availableFaces:string[]};limitations:string[];
}
