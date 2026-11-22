import {makeSnapshot} from './exports';
import {t} from './i18n';
import {reportPointNames} from './reportDisplay';
import type {FinEnergyApi} from './api';
import type {FinEnergyRecord,ReportRequest,ReportSnapshot} from './types';

export function profileChartStage(snapshot:ReportSnapshot):boolean{
 const delivery=snapshot.result.extra?.profileDelivery as {mode?:string;diagnostics?:string}|undefined;
 return snapshot.result.kind==='profile'&&delivery?.mode==='chart'&&delivery.diagnostics==='deferred';
}

export async function rebuildFullProfile(source:ReportSnapshot,api:FinEnergyApi,records:FinEnergyRecord[],signal:AbortSignal):Promise<ReportSnapshot>{
 const request={...source.request,responseMode:'full' as const};
 const result=await api.report(request,signal);
 const points=await reportPointNames(result,records,(ids,abort)=>api.resolvePoints(ids,abort),signal);
 const snapshot=makeSnapshot(source.request,result,source.title,source.project,new Date(),records,points);
 if(profileChartStage(snapshot))throw new Error(t('当前快照尚未生成完整诊断，请在分析工作台重新查询后导出。'));
 snapshot.replacesSnapshot={generatedAt:source.generatedAt,snapshotId:(source.result.extra?.profileDelivery as {snapshotId?:string}|undefined)?.snapshotId};
 return snapshot;
}
