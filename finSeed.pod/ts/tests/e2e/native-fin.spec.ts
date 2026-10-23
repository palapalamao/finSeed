import {test,expect,type APIRequestContext,type Page,type TestInfo} from '@playwright/test';
import {randomUUID} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import JSZip from 'jszip';
import type {Catalog,ReportRequest,ReportResult,SeedRecord} from '../../src/types';

// Opt-in live acceptance. The loopback bridge invokes FIN Expert against these registered
// isolated connections. It returns actual FIN responses; this file contains no business fixture.
const enabled=process.env.FINSEED_NATIVE==='1';
const bridge='http://127.0.0.1:4179/proxy';
const admin='finseed-acceptance-local';
const reader='finseed-acceptance-reader';
const project='finseed_acceptance';
const from='2026-10-19T00:00:00+08:00';
const to='2026-10-20T00:00:00+08:00';
type NativeResponse={status:number;body:unknown;audit_id?:string;trace_id?:string};
type Envelope<T>={ok:boolean;data:T;error?:{code?:string;msg?:string}};
type ProxiedCall={path:string;connection_id:string;status:number;request?:unknown;response:unknown;audit_id?:string;trace_id?:string};

async function native(request:APIRequestContext,path:string,body:unknown=undefined,connection_id=admin):Promise<NativeResponse>{
 const response=await request.post(bridge,{data:{path,...(body===undefined?{}:{body}),connection_id},timeout:60000});
 expect(response.ok(),`audited loopback bridge must be available for ${path}`).toBe(true);
 const value=await response.json() as NativeResponse;
 expect(Number.isInteger(value.status),'bridge must return the native FIN HTTP status').toBe(true);
 return value;
}
function successful<T>(response:NativeResponse):T{
 expect(response.status).toBeGreaterThanOrEqual(200);expect(response.status).toBeLessThan(300);
 const envelope=response.body as Envelope<T>;expect(envelope.ok).toBe(true);return envelope.data;
}
async function actualCatalog(request:APIRequestContext,connection_id=admin){const catalog=successful<Catalog>(await native(request,'catalog',undefined,connection_id));expect(catalog.project).toBe(project);return catalog;}
async function connectBrowser(page:Page,request:APIRequestContext,connection_id=admin){
 const calls:ProxiedCall[]=[];
 // This key satisfies the local application's transport wrapper only. It is not a FIN
 // credential, cookie, SCRAM token, or evidence of native browser-session authentication.
 await page.route('**/finStackAuth',route=>route.fulfill({status:200,headers:{'fin-stack-auth':'local-audited-bridge-only'},body:''}));
 await page.route('**/api/*/ext/enerCubix/v1/**',async route=>{
  const url=new URL(route.request().url());expect(url.origin).toBe('http://127.0.0.1:4178');
  const path=`${url.pathname.split('/v1/')[1]}${url.search}`;
  const body=route.request().method()==='POST'?route.request().postDataJSON():undefined;
  const call:ProxiedCall={path,connection_id,status:0,request:body,response:undefined};calls.push(call);
  const response=await native(request,path,body,connection_id);
  Object.assign(call,{status:response.status,response:response.body,audit_id:response.audit_id,trace_id:response.trace_id});
  await route.fulfill({status:response.status,contentType:'application/json',body:JSON.stringify(response.body)});
 });
 return calls;
}
async function evidence(testInfo:TestInfo,calls:ProxiedCall[],page:Page){const path=testInfo.outputPath('audited-native-business-e2e.json');await writeFile(path,JSON.stringify({scope:'Real FIN business API through official audited bridge; native cookie login is separate',connections:{admin,reader},project,calls},null,2));await testInfo.attach('audited-native-business-e2e.json',{path,contentType:'application/json'});await page.screenshot({path:testInfo.outputPath('native-browser-evidence.png'),fullPage:true});}

test.describe('registered FIN business acceptance through audited proxy',()=>{
 test.skip(!enabled,'Set FINSEED_NATIVE=1 only after the audited bridge and isolated FIN deployment are ready');
 test.describe.configure({mode:'serial'});

 test('real profile shows 240 kWh and exports native master point evidence',async({page,request},testInfo)=>{
  test.setTimeout(120000);const catalog=await actualCatalog(request);expect(catalog.user.canWrite).toBe(true);
  const building=catalog.records.find(record=>record.kind==='group'&&record.name==='验收楼宇');expect(building?.id).toBeTruthy();
  const calls=await connectBrowser(page,request);await page.goto(`/#/profile?project=${project}`);
  await page.locator('.object-select-button').click();
  const rootNode=page.locator('.object-panel .ant-tree-treenode').filter({has:page.getByText('验收楼宇',{exact:true})});await expect(rootNode).toBeVisible();
  await rootNode.locator('.ant-tree-checkbox').click();
  const inputs=page.locator('.filter-period input');await inputs.nth(0).fill('2026-10-19 00:00');await inputs.nth(0).press('Enter');await inputs.nth(1).fill('2026-10-20 00:00');await inputs.nth(1).press('Enter');
  await page.locator('.object-selector-drawer .ant-drawer-footer .ant-btn').click();await expect(page.locator('.object-panel')).toBeHidden();await page.getByRole('button',{name:/查\s*询/}).click();
  await expect(page.getByRole('button',{name:'导出当前报表'})).toBeVisible();
  const reportCall=calls.filter(call=>call.path==='report').at(-1)!;expect(reportCall).toBeTruthy();
  const submitted=reportCall.request as ReportRequest;expect(submitted.from).toBe(from);expect(submitted.to).toBe(to);expect(submitted.nodeIds).toEqual([building!.id]);
  const report=successful<ReportResult>({status:reportCall.status,body:reportCall.response});const totals=report.summary.totals as {value:number|null}[];
  expect(totals.some(total=>total.value===240)).toBe(true);await expect(page.locator('.metric-readout strong')).toContainText('240');
  await page.getByRole('button',{name:'导出当前报表'}).hover();const downloadEvent=page.waitForEvent('download');await page.getByRole('menuitem',{name:'Excel 工作簿 (.xlsx)',exact:true}).click();
  const download=await downloadEvent;const file=testInfo.outputPath('native-profile-240.xlsx');await download.saveAs(file);
  const zip=await JSZip.loadAsync(await readFile(file));const strings=await zip.file('xl/sharedStrings.xml')!.async('string');expect(strings).toContain('>240<');expect(strings).toContain('finseed-test-master');
  expect(calls.filter(call=>call.path==='report')).toHaveLength(1);await page.screenshot({path:testInfo.outputPath('native-profile-240.png'),fullPage:true});
  await page.evaluate(()=>{const target=window as unknown as {nativePrintCalled:boolean};target.nativePrintCalled=false;window.print=()=>{target.nativePrintCalled=true;};});await page.getByRole('button',{name:'打印'}).click();expect(await page.evaluate(()=>(window as unknown as {nativePrintCalled:boolean}).nativePrintCalled)).toBe(true);
  await page.emulateMedia({media:'print'});await expect(page.locator('.desktop-nav')).toBeHidden();await expect(page.locator('.filter-panel')).toBeHidden();await expect(page.locator('.report-surface')).toBeVisible();const printed=await page.pdf({path:testInfo.outputPath('native-print.pdf'),format:'A4',landscape:true,printBackground:true});expect(printed.subarray(0,5).toString()).toBe('%PDF-');expect(printed.length).toBeGreaterThan(10000);await page.emulateMedia({media:'screen'});await evidence(testInfo,calls,page);
 });

 test('real group create, persistent refresh and delete use only a unique acceptance record',async({page,request},testInfo)=>{
  test.setTimeout(120000);const name=`浏览器原生验收-${randomUUID().slice(0,12)}`;const calls=await connectBrowser(page,request);let createdId:string|undefined;let outcomeUnknown=false;
  try{
   await page.goto(`/#/tree?project=${project}`);await page.getByRole('button',{name:'新增分组'}).click();await page.getByLabel('名称',{exact:true}).fill(name);await page.getByLabel('建筑面积 (m²)',{exact:true}).fill('321');await page.getByRole('button',{name:'保存配置',exact:true}).click();
   await expect.poll(()=>calls.filter(call=>call.path==='records'&&call.status!==0).length).toBe(1);const create=calls.find(call=>call.path==='records')!;
   outcomeUnknown=JSON.stringify(create.response).includes('outcome_unknown');expect(outcomeUnknown,'Never retry a mutation with an unknown outcome').toBe(false);
   const saved=successful<SeedRecord>({status:create.status,body:create.response});createdId=saved.id;expect(createdId).toBeTruthy();expect(saved.name).toBe(name);expect(saved.area).toBe(321);
   await page.getByPlaceholder('搜索配置名称').fill(name);await expect(page.getByRole('button',{name,exact:true})).toBeVisible();
   await page.locator('.workspace-title').getByRole('button',{name:/刷新/}).click();await expect(page.getByRole('button',{name,exact:true})).toBeVisible();
   const persisted=(await actualCatalog(request)).records.find(record=>record.id===createdId);expect(persisted?.name).toBe(name);expect(persisted?.area).toBe(321);
   await page.screenshot({path:testInfo.outputPath('native-group-persisted.png'),fullPage:true});
   await page.getByRole('button',{name:`删除${name}`,exact:true}).click();await page.getByRole('button',{name:/^删\s*除$/}).click();
   await expect(page.getByRole('button',{name,exact:true})).toHaveCount(0);const deletion=calls.filter(call=>call.path==='records/delete').at(-1)!;expect(deletion).toBeTruthy();outcomeUnknown=JSON.stringify(deletion.response).includes('outcome_unknown');expect(outcomeUnknown).toBe(false);successful({status:deletion.status,body:deletion.response});
   expect((await actualCatalog(request)).records.some(record=>record.id===createdId)).toBe(false);createdId=undefined;await evidence(testInfo,calls,page);
  }finally{
   // Reconcile with a fresh read before cleanup; never retry an outcome_unknown mutation.
   const uncertain=calls.some(call=>['records','records/delete'].includes(call.path)&&(call.status===0||JSON.stringify(call.response).includes('outcome_unknown')));
   if(createdId&&!outcomeUnknown&&!uncertain){const remaining=(await actualCatalog(request)).records.find(record=>record.id===createdId&&record.kind==='group'&&record.name===name);if(remaining)successful(await native(request,'records/delete',{id:remaining.id,mod:remaining.mod}));}
  }
 });

 test('real reader catalog disables controls and native record mutation is forbidden',async({page,request},testInfo)=>{
  test.setTimeout(120000);const catalog=await actualCatalog(request,reader);expect(catalog.user.canWrite).toBe(false);const calls=await connectBrowser(page,request,reader);
  await page.goto(`/#/tree?project=${project}`);await expect(page.getByRole('button',{name:'新增分组'})).toBeDisabled();
  const name=`只读拒绝验收-${randomUUID().slice(0,12)}`;
  const response=await page.evaluate(async({project,name})=>{const response=await fetch(`/api/${project}/ext/enerCubix/v1/records`,{method:'POST',headers:{'Content-Type':'application/json','skyarc-attest-key':'local-audited-bridge-only'},body:JSON.stringify({record:{kind:'group',name,area:321}})});return {status:response.status,body:await response.json()};},{project,name});
  expect(response.status).toBe(403);expect(response.body.ok).toBe(false);expect((await actualCatalog(request,reader)).records.some(record=>record.name===name)).toBe(false);
  expect(calls.find(call=>call.path==='records')?.connection_id).toBe(reader);await evidence(testInfo,calls,page);
 });
});
