import type {BudgetConfig,RuleConfig,CockpitConfigList,CockpitConfigAudit} from './cockpitConfig';
import {serverMessage,t} from './i18n';
import {finCsrfFetch} from 'haystack-nclient';
import type {Catalog,ComparisonScope,FinPoint,ReportRequest,ReportResult,EnerCubixRecord} from './types';
import type {CleaningPreview} from './cleaning';
import type {ChangeMessagePage} from './changeMessages';
import type {CockpitAsset,CockpitAssetCatalog,CockpitHotspot} from './cockpitAssets';
import type {CockpitRequest,CockpitSnapshot} from './cockpitTypes';
import {decodeCockpitPayload} from './cockpitPayload';
import type {LicenseStatus} from './license';
export class ApiError extends Error {constructor(public code:string,message:string,public sourceMessage?:string){super(message);this.name='ApiError';}}
export function unwrap<T>(value:unknown,status=200):T {
 if(!value||typeof value!=='object')throw new ApiError('invalid_response',t("FIN 返回了无效的响应。请检查项目和服务状态。"),"FIN 返回了无效的响应。请检查项目和服务状态。");
 const body=value as {ok?:boolean;data?:T;error?:{code?:string;msg?:string}};
 if(body.ok!==true||status<200||status>=300)throw new ApiError(body.error?.code||`http_${status}`,body.error?.msg?serverMessage(body.error.msg):t("请求失败，请检查当前 FIN 会话与项目权限。"),body.error?.msg||"请求失败，请检查当前 FIN 会话与项目权限。");
 if(!('data'in body))throw new ApiError('invalid_response',t("FIN 响应缺少数据。"),"FIN 响应缺少数据。");return body.data as T;
}
export {projectFromLocation} from './projectLocation';
export class EnerCubixApi {
 readonly base:string;
 constructor(project:string,private onSessionExpired?:()=>void){if(!project)throw new ApiError('missing_project',t("请在 FIN 项目内打开能源魔方，或在地址的 #/profile?project=项目名 中指定项目。"),"请在 FIN 项目内打开能源魔方，或在地址的 #/profile?project=项目名 中指定项目。");this.base=`/api/${encodeURIComponent(project)}/ext/enerCubix/v1`;}
 async request<T>(path:string,body?:unknown,signal?:AbortSignal):Promise<T>{
  let response:Response;
  try{response=await finCsrfFetch(`${this.base}/${path}`,{method:body===undefined?'GET':'POST',headers:{Accept:'application/json',...(body===undefined?{}:{'Content-Type':'application/json'})},body:body===undefined?undefined:JSON.stringify(body),credentials:'same-origin',signal});}
  catch(error){if(error instanceof Error&&error.name==='AbortError')throw error;if(error&&typeof error==='object'&&'status'in error){if(error.status===401){this.onSessionExpired?.();throw new ApiError('unauthorized',t("FIN 会话已过期，请在 FIN 中重新登录。"),"FIN 会话已过期，请在 FIN 中重新登录。");}if(error.status===403)throw new ApiError('forbidden',t("当前 FIN 会话无权访问此项目。"),"当前 FIN 会话无权访问此项目。");if('_isCsrfError'in error&&error._isCsrfError){this.onSessionExpired?.();throw new ApiError('session_expired',t("FIN 会话已失效，请在 FIN 中重新登录。"),"FIN 会话已失效，请在 FIN 中重新登录。");}}throw new ApiError('network',t("无法连接 FIN，请检查网络与当前会话。"),"无法连接 FIN，请检查网络与当前会话。");}
  let value:unknown;try{value=await response.json();}catch{const login=response.status===401||response.redirected||(response.headers.get('content-type')||'').includes('text/html');if(login)this.onSessionExpired?.();throw new ApiError(login?'session_expired':'invalid_response',login?t("FIN 会话已失效，请在 FIN 中重新登录。"):t("FIN 未返回 JSON，请检查项目名称及能源魔方扩展是否已启用。"),login?"FIN 会话已失效，请在 FIN 中重新登录。":"FIN 未返回 JSON，请检查项目名称及能源魔方扩展是否已启用。");}
  try{return unwrap<T>(value,response.status);}catch(error){if(response.status===401||error instanceof ApiError&&(['session_expired','unauthorized','http_401'].includes(error.code)))this.onSessionExpired?.();throw error;}
 }
 budgets=()=>this.request<CockpitConfigList<BudgetConfig>>('cockpit/budgets');
 ruleProfiles=()=>this.request<CockpitConfigList<RuleConfig>>('cockpit/rule-profiles');
 saveBudget=(body:Record<string,unknown>)=>this.request<BudgetConfig>('cockpit/budgets/save',body);
 saveRuleProfile=(body:Record<string,unknown>)=>this.request<RuleConfig>('cockpit/rule-profiles/save',body);
 deleteCockpitConfig=(type:'budget'|'rule',record:{id?:string;mod?:string})=>this.request<{deleted:string}>('cockpit/'+(type==='budget'?'budgets':'rule-profiles')+'/delete',{id:record.id,mod:record.mod});
 cockpitConfigAudit=(targetId:string)=>this.request<CockpitConfigAudit>('cockpit/config-audit?targetId='+encodeURIComponent(targetId));
 catalog=()=>this.request<Catalog>('catalog');
 licenseStatus=(signal?:AbortSignal)=>this.request<LicenseStatus>('license/status',undefined,signal);
 importLicense=(license:string)=>this.request<LicenseStatus>('license/import',{license});
 assets=(signal?:AbortSignal)=>this.request<CockpitAssetCatalog>('cockpit/assets',undefined,signal);
 uploadAsset=(body:{id?:string;mod?:string;manifestMod:string|null;scopeId:string;name:string;base64:string;clearHotspots?:boolean})=>this.request<CockpitAssetCatalog>('cockpit/assets/upload',body);
 saveAsset=(body:{id:string;mod:string;manifestMod:string|null;scopeId:string;name:string;hotspots:CockpitHotspot[]})=>this.request<CockpitAssetCatalog>('cockpit/assets/save',body);
 selectAsset=(id:string|null,manifestMod:string|null)=>this.request<CockpitAssetCatalog>('cockpit/assets/select',{id,manifestMod});
 deleteAsset=(asset:Pick<CockpitAsset,'id'|'mod'>,manifestMod:string|null)=>this.request<CockpitAssetCatalog>('cockpit/assets/delete',{id:asset.id,mod:asset.mod,manifestMod});
 assetImageUrl=(asset:Pick<CockpitAsset,'id'|'hash'>)=>this.base+'/cockpit/assets/image?id='+encodeURIComponent(asset.id)+'&hash='+encodeURIComponent(asset.hash);
 points=(q:string,offset=0,limit=100)=>this.request<{items:FinPoint[];total:number;offset:number;limit:number}>(`points?q=${encodeURIComponent(q)}&offset=${offset}&limit=${limit}`);
 save=(record:EnerCubixRecord)=>this.request<EnerCubixRecord>('records',{record});
 remove=(record:EnerCubixRecord)=>this.request<{deleted:string}>('records/delete',{id:record.id,mod:record.mod});
 cleaningPreview=(body:{nodeId:string;from:string;to:string},signal?:AbortSignal)=>this.request<CleaningPreview>('cleaning/preview',body,signal);
 tree=(action:'copy'|'move',record:EnerCubixRecord,parentId:string)=>this.request<{records:EnerCubixRecord[]}>(`tree/${action}`,{id:record.id,mod:record.mod,parentId});
 manage=<T>(action:string,body:Record<string,unknown>)=>this.request<T>('tree/manage',{...body,action});
 migrationPreview=()=>this.request<MigrationPreview>('migration/preview');
 migration=(body:Record<string,unknown>)=>this.request<{job:EnerCubixRecord|null;applied?:number}>('migration',body);
 report=(request:ReportRequest,signal?:AbortSignal)=>this.request<ReportResult>('report',request,signal);
 cockpit=async(request:CockpitRequest,signal?:AbortSignal):Promise<CockpitSnapshot>=>{
  const data=await this.request<unknown>('cockpit',{...request,payloadEncoding:'compact-v1'},signal);
  try{return decodeCockpitPayload<CockpitSnapshot>(data);}
  catch{throw new ApiError('invalid_response',t('FIN 返回了无效的响应。请检查项目和服务状态。'),'FIN 返回了无效的响应。请检查项目和服务状态。');}
 };
 comparisonScopes=(nodeIds:string[],signal?:AbortSignal)=>this.request<{scopes:ComparisonScope[]}>(`comparison-scopes?nodeIds=${encodeURIComponent(nodeIds.join(','))}`,undefined,signal);
 alarms=()=>this.request<EnerCubixRecord[]>('alarms');
 changeMessages=(offset=0,limit=30,signal?:AbortSignal)=>this.request<ChangeMessagePage>(`messages/changes?offset=${offset}&limit=${limit}`,undefined,signal);
 ack=(record:EnerCubixRecord,note:string)=>this.request<EnerCubixRecord>('alarms/ack',{id:record.id,mod:record.mod,note});
 task=(body:{action:string;enabled?:boolean;from?:string;to?:string})=>this.request<EnerCubixRecord>('tasks',body);
}
export interface MigrationPreview {target?:'nativeEquip';conflicts?:string[];alreadyApplied?:boolean;version:number;revision:string;sourceRevision?:string;records:EnerCubixRecord[];suggestions:{id:string;type:string;title:string;reason:string;requiresConfirmation:boolean;placementRequired?:boolean;records:EnerCubixRecord[];sourceIds:string[];recordIds:string[]}[];warnings:string[];counts:{added:number;updated:number;canonicalAliases:number;spaces:number;suggestions:number;unboundMeters:number}}
