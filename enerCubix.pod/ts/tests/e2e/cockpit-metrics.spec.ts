import {test,expect,type Page} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';
const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-metrics-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;

async function setup(page:Page,language:string){
 const state=await installTransport(page,{userLocale:language,spaceSource:'fin',records:[{id:'s',kind:'space',name:'真实园区',nativeReadonly:true,nativeSourceKind:'site'},{id:'a',kind:'meter',name:'电表原名',pointId:'pa',categoryId:'c',nativeEquip:true,nativeTreeParentId:'s'},{id:'w',kind:'meter',name:'水表原名',pointId:'pw',categoryId:'water',nativeEquip:true,nativeTreeParentId:'s'},{id:'pa',kind:'nativePoint',name:'电能',parentId:'a',his:true,energyTags:['elec']},{id:'pw',kind:'nativePoint',name:'水量',parentId:'w',his:true,energyTags:['water']},{id:'c',kind:'category',name:'电力原名',unit:'kWh'},{id:'water',kind:'category',name:'水原名',unit:'m³'}]});
 await page.route('**/api/testproject/ext/enerCubix/v1/catalog',route=>route.fulfill({status:200,json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}}));
 const requests:CockpitRequest[]=[],control={mode:'complete',status:200};
 await page.route('**/api/testproject/ext/enerCubix/v1/cockpit',route=>{
  const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);
  if(control.status!==200)return route.fulfill({status:409,json:{ok:false,error:{code:'CONFIGURATION_CHANGED',msg:'cockpitConfigurationChanged'}}});
  const snapshot=structuredClone(raw);snapshot.requestId=request.requestId;snapshot.snapshotId='metric-'+requests.length;snapshot.context.project='testproject';snapshot.context.reportScope=request.reportScope;snapshot.context.auxiliaryCategoryId=request.auxiliaryCategoryId;snapshot.context.time={...snapshot.context.time,...request.time,from:request.time.from||raw.context.time.from,to:request.time.to||raw.context.time.to};
  snapshot.context.comparison={...snapshot.context.comparison,...request.comparison,mode:request.time.preset==='custom'&&request.comparison?.mode==='presetDefault'?'none':request.comparison?.mode||'none'};
  const values=snapshot.modules.kpis!.data!.values,energy=values.find(v=>v.id==='energy')!;
  if(control.mode==='partial'){energy.value=70;energy.completeValue=null;energy.valueBasis='knownSubtotal';energy.reasonCodes=['partial'];energy.comparison={...energy.comparison!,comparable:false,changeRate:null,reasonCodes:['INCOMPLETE_COVERAGE']};}
  if(control.mode==='fallback'){values[2]={id:'areaIntensity',value:null,valueType:'null',unit:'kWh/m²',quality:'missingArea',valueBasis:'unavailable',sourceIds:[],reasonCodes:['missingArea']};values[3]={id:'activeAlarms',value:0,valueType:'number',unit:'count',quality:'ok',valueBasis:'currentState',sourceIds:[],stateObservedAt:snapshot.generatedAt};}
  if(control.mode==='waterMissing'){values[2]={...values[2],value:null,completeValue:null,valueBasis:'unavailable',reasonCodes:['missing']};}
  if(control.mode!=='complete'){const id=control.mode==='partial'?'energy':control.mode==='fallback'?'areaIntensity':'auxiliaryEnergy';snapshot.modules.kpis!.status='partial';snapshot.modules.kpis!.data!.conclusions=[{id:'dataQuality',ruleId:'CPT02-dataQuality',ruleVersion:1,messageKey:'cockpit.conclusion.dataQuality',args:{metricId:id,reasonCodes:values.find(value=>value.id===id)?.reasonCodes||[]},evidenceRefs:[],priority:1}];}return route.fulfill({status:200,json:{ok:true,data:snapshot}});
 });
 return {requests,control};
}
for(const language of ['zh-CN','en-US']){
 test('four frozen KPI cards, incomplete comparison and conflict preservation '+language,async({page})=>{
  const {requests,control}=await setup(page,language);await page.goto('/#/cockpit?project=testproject');
  await expect(page.locator('.cockpit-kpi')).toHaveCount(4);await expect(page.locator('[data-metric="cost"] .cockpit-card-number')).toHaveText('200 CNY');await expect(page.locator('.cockpit-number')).toHaveText('100 kWh');await expect(page.locator('[data-metric="auxiliaryEnergy"]')).toContainText('水原名');expect(requests[0]).toMatchObject({auxiliaryCategoryId:'water',comparison:{mode:'presetDefault'}});
  await expect(page.locator('[data-metric="energy"] .cockpit-card-comparison')).toContainText('+25%');
  await page.locator('[data-metric="energy"]>details>summary').click();await expect(page.locator('[data-metric="energy"]')).toContainText('2026-10-02 00:00:00Z');expect(requests).toHaveLength(1);
  control.mode='partial';await page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true}).click();await expect(page.locator('.cockpit-number')).toHaveText('70 kWh');await expect(page.locator('[data-metric="energy"] .cockpit-card-comparison')).not.toContainText('%');
  const count=requests.length;control.status=409;await page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true}).click();await expect(page.locator('.cockpit-page')).toContainText(language==='zh-CN'?'准备查询期间配置已变化':'Configuration changed while preparing');await expect(page.locator('.cockpit-number')).toHaveText('70 kWh');expect(requests).toHaveLength(count+1);
  await page.screenshot({path:'test-results/cockpit-metrics-'+language+'-desktop.png',fullPage:true});
 });
 test('fallback, independent water failure, explicit dates and mobile '+language,async({page})=>{
  const {requests,control}=await setup(page,language);control.mode='waterMissing';await page.goto('/#/cockpit?project=testproject');await expect(page.locator('.cockpit-number')).toHaveText('100 kWh');await expect(page.locator('[data-metric="auxiliaryEnergy"] .cockpit-card-number')).toHaveText('— m³');
  control.mode='fallback';await page.locator('.cockpit-conditions-trigger').click();await page.locator('.cockpit-controls-more>summary').click();await page.locator('.cockpit-controls').getByText('水原名',{exact:true}).click();await page.getByText(language==='zh-CN'?'单位面积用量':'Usage per unit area',{exact:true}).last().click();await page.getByRole('button',{name:language==='zh-CN'?'应用条件':'Apply conditions',exact:true}).click();await expect(page.locator('[data-metric="areaIntensity"]')).toBeVisible();await expect(page.locator('[data-metric="activeAlarms"] .cockpit-card-number')).toHaveText(language==='zh-CN'?'0 个':'0 count');
  const count=requests.length;await page.locator('.cockpit-controls').getByText(language==='zh-CN'?'本月':'This month',{exact:true}).click();await page.getByText(language==='zh-CN'?'自定义时间':'Custom period',{exact:true}).last().click();await expect(page.locator('.cockpit-date-note')).toBeVisible();expect(requests).toHaveLength(count);
  await page.getByRole('button',{name:language==='zh-CN'?'应用条件':'Apply conditions',exact:true}).click();await expect.poll(()=>requests.length).toBe(count+1);expect(requests.at(-1)?.time).toMatchObject({preset:'custom',from:raw.context.time.from,to:raw.context.time.to});await expect(page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true})).toBeVisible();
  for(const width of [320,390]){await page.setViewportSize({width,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth),{message:'Chart ResizeObserver must settle within the mobile viewport'}).toBeLessThanOrEqual(width);await expect(page.locator('[data-metric="activeAlarms"]')).toBeVisible();await page.screenshot({path:'test-results/cockpit-metrics-'+language+'-'+width+'.png',fullPage:true});}
 });
}
test('promoting a focus keeps the applied absolute period rather than submitting unrelated draft filters',async({page})=>{
 const {requests}=await setup(page,'en-US');await page.goto('/#/cockpit?project=testproject');await expect(page.locator('.cockpit-number')).toHaveText('100 kWh');
 await page.locator('.cockpit-conditions-trigger').click();await page.locator('.cockpit-controls').getByText('This month',{exact:true}).click();await page.getByText('Today',{exact:true}).last().click();expect(requests).toHaveLength(1);
 await page.getByRole('button',{name:'真实园区 / 电表原名',exact:true}).click();await page.getByRole('button',{name:'Set as statistical scope'}).click();await expect.poll(()=>requests.length).toBe(2);
 expect(requests[1]).toMatchObject({reportScope:{nodeIds:['a']},time:{preset:'custom',from:raw.context.time.from,to:raw.context.time.to},asOf:raw.context.asOf});
});
