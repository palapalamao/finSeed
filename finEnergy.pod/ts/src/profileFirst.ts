import {makeSnapshot} from './exports';
import {t} from './i18n';
import {reportPointNames} from './reportDisplay';
import type {FinEnergyApi} from './api';
import type {FinEnergyRecord,ReportRequest,ReportSnapshot} from './types';

export function profileChartStage(snapshot:ReportSnapshot):boolean{
 const delivery=snapshot.result.extra?.profileDelivery as {mode?:string;diagnostics?:string}|undefined;
 return snapshot.result.kind==='profile'&&delivery?.mode==='chart'&&delivery.diagnostics==='deferred';
}

// The server independently checks the catalog and uses the full path for any
// unsupported selection. Do not save a delivery preference in report templates.
export function chartFirstRequest(request:ReportRequest):ReportRequest{
 return request.kind==='profile'&&request.metric==='energy'&&request.period==='day'&&request.dimension==='space'&&request.spaceSource==='fin'&&!request.perArea&&!request.referenceIds?.length&&!request.otherFrom&&!request.otherTo?{...request,responseMode:'chart'}:request;
}

export async function rebuildFullProfile(source:ReportSnapshot,api:FinEnergyApi,records:FinEnergyRecord[],signal:AbortSignal):Promise<ReportSnapshot>{
 const request={...source.request,responseMode:'full' as const};
 const result=await api.report(request,signal);
 const points=await reportPointNames(result,records,id=>api.points(id,0,10));
 const snapshot=makeSnapshot(source.request,result,source.title,source.project,new Date(),records,points);
 if(profileChartStage(snapshot))throw new Error(t('当前快照尚未生成完整诊断，请在分析工作台重新查询后导出。'));
 snapshot.replacesSnapshot={generatedAt:source.generatedAt,snapshotId:(source.result.extra?.profileDelivery as {snapshotId?:string}|undefined)?.snapshotId};
 return snapshot;
}
