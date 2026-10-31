import type {ReportResult} from './types';

export interface CockpitScope {dimension:'space'|'metering'|'organization';nodeIds:string[];selectionIntent:'range'|'explicitObjects'}
export interface CockpitRequest {
 schemaVersion:1;requestId:string;reportScope:CockpitScope;focusCategoryId:string;auxiliaryCategoryId?:string;
 time:{preset:'today'|'thisMonth'|'thisYear'|'custom';period:'hour'|'day'|'month';from?:string;to?:string};
 asOf?:string;modules:('kpis'|'trend')[];comparison?:{mode:'none'|'presetDefault'|'custom';from?:string;to?:string};
}
export interface CockpitMetric {
 id:string;categoryId?:string;value:number|null;valueType:'number'|'na'|'null';unit:string;quality:string;
 valueBasis:'complete'|'knownSubtotal'|'cleanedWithReplacement'|'unavailable'|'currentState';
 completeValue?:number|null;knownValue?:number|null;sourceIds:string[];reasonCodes?:string[];
 comparison?:{kind:string;currentRange:{from:string;to:string};referenceRange:{from:string;to:string};current:number|null;reference:number|null;comparable:boolean;difference:number|null;changeRate:number|null;reasonCodes:string[];durationDifferenceSeconds:number};
 details?:Record<string,unknown>;coverage?:Record<string,unknown>[];stateObservedAt?:string|null;
}
export interface CockpitConclusion {id:string;ruleId:string;ruleVersion:number;messageKey:string;args:Record<string,unknown>;evidenceRefs:string[];priority:number}
export interface CockpitModule<T> {status:'ok'|'partial'|'empty'|'unavailable'|'error';data?:T;reasonCodes?:string[];error?:{code:string;message?:string}}
export interface CockpitSnapshot {
 schemaVersion:1;snapshotId:string;requestId:string;generatedAt:string;
 context:{project:string;projectTimeZone:string;reportScope:CockpitScope;focusCategoryId:string;auxiliaryCategoryId?:string;time:CockpitRequest['time']&{from:string;to:string};asOf:string;comparison?:CockpitRequest['comparison']};
 provenance:{configFingerprint:string;relationshipBasis:'currentConfiguration';historyBasis:'ownPrimaryPointRaw';historyObservedFrom:string;historyObservedTo:string;sourceLastObservedAt:string|null;configRefs:{id:string;mod?:string}[];historyPlan?:{from:string;to:string;pointIds:string[]}[];appliedCleaning?:{pointId:string;profileId:string;profileVersion:number;parameters:Record<string,unknown>}[];historyConfigObservedFrom?:string|null;historyConfigObservedTo?:string|null};
 boundary:{id:string;meterIds:string[];sourcePointIds:string[];aggregateAllowed:boolean;overlaps:unknown[];excluded:unknown[]};
 modules:{kpis?:CockpitModule<{values:CockpitMetric[];conclusions:CockpitConclusion[]}>;trend?:CockpitModule<{reportRef:string}>};
 reports:Record<string,ReportResult>;quality:Record<string,unknown>[];
 capabilities:{canRead:boolean;canManage:boolean;availableFaces:string[]};limitations:string[];
}
