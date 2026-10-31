import type {ReportResult} from './types';

export interface CockpitScope {dimension:'space'|'metering'|'organization';nodeIds:string[];selectionIntent:'range'|'explicitObjects'}
export interface CockpitRequest {
 schemaVersion:1;requestId:string;reportScope:CockpitScope;focusCategoryId:string;
 time:{preset:'today'|'thisMonth'|'thisYear'|'custom';period:'hour'|'day'|'month';from?:string;to?:string};
 asOf?:string;modules:('kpis'|'trend')[];comparison?:{mode:'none'};
}
export interface CockpitMetric {
 id:string;categoryId?:string;value:number|null;valueType:'number'|'na'|'null';unit:string;quality:string;
 valueBasis:'complete'|'knownSubtotal'|'cleanedWithReplacement'|'unavailable';
 completeValue?:number|null;knownValue?:number|null;sourceIds:string[];reasonCodes?:string[];
}
export interface CockpitModule<T> {status:'ok'|'partial'|'empty'|'unavailable'|'error';data?:T;reasonCodes?:string[];error?:{code:string;message?:string}}
export interface CockpitSnapshot {
 schemaVersion:1;snapshotId:string;requestId:string;generatedAt:string;
 context:{project:string;projectTimeZone:string;reportScope:CockpitScope;focusCategoryId:string;time:CockpitRequest['time']&{from:string;to:string};asOf:string};
 provenance:{configFingerprint:string;relationshipBasis:'currentConfiguration';historyBasis:'ownPrimaryPointRaw';historyObservedFrom:string;historyObservedTo:string;sourceLastObservedAt:string|null;configRefs:{id:string;mod?:string}[]};
 boundary:{id:string;meterIds:string[];sourcePointIds:string[];aggregateAllowed:boolean;overlaps:unknown[];excluded:unknown[]};
 modules:{kpis?:CockpitModule<{values:CockpitMetric[];conclusions:unknown[]}>;trend?:CockpitModule<{reportRef:string}>};
 reports:Record<string,ReportResult>;quality:Record<string,unknown>[];
 capabilities:{canRead:boolean;canManage:boolean;availableFaces:string[]};limitations:string[];
}
