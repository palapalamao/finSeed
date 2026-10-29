import {finCsrfFetch} from 'haystack-nclient';
import {projectFromLocation} from './projectLocation';
import {t} from './i18n';

/** Read the authenticated FIN request locale before loading translated UI modules. */
export async function loadFinLocale(location:Pick<Location,'hash'|'search'|'pathname'>):Promise<string>{
 const project=projectFromLocation(location);
 if(!project)throw new Error(t('尚未指定 FIN 项目'));
 let response:Response;
 try{response=await finCsrfFetch(`/api/${encodeURIComponent(project)}/ext/enerCubix/v1/session`,{
  method:'GET',headers:{Accept:'application/json'},credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(15000)
 });}catch(error){
  if(error&&typeof error==='object'){
   if('status'in error&&error.status===403)throw new Error(t('当前 FIN 会话无权访问此项目。'));
   if(('status'in error&&error.status===401)||('_isCsrfError'in error&&error._isCsrfError))throw new Error(t('FIN 会话已失效，请在 FIN 中重新登录。'));
  }
  throw new Error(t('无法连接 FIN，请检查网络与当前会话。'));
 }
 if(response.status===403)throw new Error(t('当前 FIN 会话无权访问此项目。'));
 if(response.status===401||response.redirected||(response.headers.get('content-type')||'').includes('text/html'))throw new Error(t('FIN 会话已失效，请在 FIN 中重新登录。'));
 let body:{ok?:boolean;data?:{locale?:unknown}};
 try{body=await response.json();}catch{throw new Error(t('无法读取 FIN 用户语言，请重新打开应用。'));}
 if(!response.ok||body.ok!==true||typeof body.data?.locale!=='string'||!body.data.locale.trim())throw new Error(t('无法读取 FIN 用户语言，请重新打开应用。'));
 return body.data.locale;
}
