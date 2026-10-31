import {test,expect,type Page} from '@playwright/test';
import {installTransport,resultFor,type TransportState} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';
import type {ReportRequest} from '../../src/types';
import {readFileSync} from 'node:fs';
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version as string;

function response(request:CockpitRequest,value:number|null=40):CockpitSnapshot{
 const from='2026-10-01T00:00:00+08:00',to='2026-10-31T14:37:00+08:00';
 const reportRequest:ReportRequest={kind:'profile',nodeIds:request.reportScope.nodeIds,from,to,metric:'energy',period:request.time.period,perArea:false};
 const result=resultFor(reportRequest,value===null);result.series[0].points[0].value=value;
 return {schemaVersion:1,snapshotId:'snapshot-'+request.requestId,requestId:request.requestId,generatedAt:'2026-10-31T14:37:03+08:00',context:{project:'testproject',projectTimeZone:'Asia/Shanghai',reportScope:request.reportScope,focusCategoryId:request.focusCategoryId,time:{...request.time,from,to},asOf:to},provenance:{configFingerprint:'frozen-config',relationshipBasis:'currentConfiguration',historyBasis:'ownPrimaryPointRaw',historyObservedFrom:to,historyObservedTo:'2026-10-31T14:37:02+08:00',sourceLastObservedAt:'2026-10-31T14:36:00+08:00',configRefs:[]},boundary:{id:'b',meterIds:['meter1'],sourcePointIds:['point1'],aggregateAllowed:true,overlaps:[],excluded:[]},modules:{kpis:{status:value===null?'unavailable':'partial',data:{values:[{id:'energy',categoryId:request.focusCategoryId,value,valueType:value===null?'null':'number',unit:'kWh',quality:value===null?'missing':'partial',valueBasis:value===null?'unavailable':'knownSubtotal',sourceIds:['point1']}],conclusions:[]}},trend:{status:'ok',data:{reportRef:'profile-energy'}}},reports:{'profile-energy':result},quality:[],capabilities:{canRead:true,canManage:false,availableFaces:[]},limitations:['PARTIAL_USAGE']};
}
async function setup(page:Page,options:Partial<TransportState>={}){
 const state=await installTransport(page,options);
 state.records.push({id:'site',kind:'space',name:'真实园区名称',nativeReadonly:true,nativeSourceKind:'site'});
 await page.route('**/api/testproject/ext/enerCubix/v1/catalog',route=>route.fulfill({status:200,json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:'test-user',canWrite:state.canWrite},records:state.records}}}));
 const requests:CockpitRequest[]=[];const control={status:200,value:40 as number|null};
 await page.route('**/api/testproject/ext/enerCubix/v1/cockpit',async route=>{
  const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);
  if(control.status!==200){await route.fulfill({status:control.status,json:{ok:false,error:{code:'INTERNAL',msg:'fixture unavailable'}}});return;}
  await route.fulfill({status:200,json:{ok:true,data:response(request,control.value)}});
 });
 return {state,requests,control};
}
for(const language of ['zh-CN','en-US']){
 test('cockpit real scope, frozen zero, failure and legacy fallback '+language,async({page})=>{
  const {requests,control}=await setup(page,{userLocale:language,canWrite:false});
  await page.goto('/#/cockpit?project=testproject');
  await expect(page.getByRole('heading',{name:language==='zh-CN'?'能源经营驾驶舱':'Energy operations cockpit'})).toBeVisible();
  await expect(page.locator('.cockpit-number')).toHaveText('40 kWh');
  await expect(page.locator('.cockpit-trend canvas')).toBeVisible();
  await page.screenshot({path:'test-results/cockpit-'+language+'-desktop.png',fullPage:true});
  expect(requests).toHaveLength(1);expect(requests[0]).toMatchObject({reportScope:{dimension:'space',nodeIds:['site']},time:{preset:'thisMonth'}});
  await expect(page.locator('.cockpit-context')).toContainText('真实园区名称');
  control.value=0;await page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true}).click();
  await expect(page.locator('.cockpit-number')).toHaveText('0 kWh');
  control.status=500;await page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true}).click();
  await expect(page.getByText('fixture unavailable',{exact:true})).toBeVisible();
  await expect(page.locator('.cockpit-number')).toHaveText('0 kWh');
  await expect(page.getByText(language==='zh-CN'?'当前保留上次成功快照，范围和时间以此处标注为准。':'The previous successful snapshot is retained. Its scope and period are shown below.')).toBeVisible();
  const count=requests.length;await page.getByText(language==='zh-CN'?'查看趋势明细与数据来源':'View trend values and data sources',{exact:true}).click();
  await expect(page.locator('.cockpit-details')).toContainText('point1');expect(requests).toHaveLength(count);
  await page.getByRole('button',{name:language==='zh-CN'?'旧版总览':'Legacy overview'}).click();
  await expect(page).toHaveURL(/#\/dashboard\?project=testproject/);
 });
 test('cockpit mobile layout and no-history state '+language,async({page})=>{
  const {control}=await setup(page,{userLocale:language});control.value=null;
  await page.setViewportSize({width:320,height:800});await page.goto('/#/cockpit?project=testproject');
  await expect(page.locator('.cockpit-number')).toHaveText('— kWh');
  await expect(page.locator('.cockpit-trend .ant-empty')).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
  await page.screenshot({path:'test-results/cockpit-'+language+'-320.png',fullPage:true});
  await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 });
}
test('draft range changes do not relabel prior data or query until applied',async({page})=>{
 const {requests}=await setup(page,{userLocale:'en-US'});await page.goto('/#/cockpit?project=testproject');await expect(page.locator('.cockpit-number')).toHaveText('40 kWh');
 const count=requests.length;await page.locator('.cockpit-controls').getByText('This month',{exact:true}).click();await page.getByText('Today',{exact:true}).last().click();
 await expect(page.getByText('Conditions not applied',{exact:true})).toBeVisible();expect(requests).toHaveLength(count);
 await expect(page.locator('.cockpit-context')).toContainText('2026-10-01');
 await page.getByRole('button',{name:'Apply conditions',exact:true}).click();await expect.poll(()=>requests.length).toBe(count+1);
 expect(requests.at(-1)?.time.preset).toBe('today');
});
