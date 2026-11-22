import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport,openCockpitActions} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';
const fixture=JSON.parse(readFileSync(new URL('../fixtures/cockpit-presentation-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
for(const language of ['zh-CN','en-US'])test('loads and caches independent cockpit faces '+language,async({page},testInfo)=>{
 const state=await installTransport(page,{userLocale:language,records:[
  {id:'plant',kind:'space',name:'Plant',nativeSourceKind:'site'},
  {id:'elec',kind:'category',name:'Electricity',unit:'kWh'},
  {id:'in',kind:'meter',name:'Input meter',pointId:'pi',categoryId:'elec',spaceId:'plant'}]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog',route=>route.fulfill({json:{ok:true,data:{project:'testproject',version,edition:'china',licenseMode:'selfManaged',user:{name:state.username,canWrite:false},records:state.records}}}));
 const requests:CockpitRequest[]=[];let fail=false;
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{
  const q=route.request().postDataJSON() as CockpitRequest;requests.push(q);
  if(fail)return route.fulfill({status:409,json:{ok:false,error:{code:'COCKPIT_CONFIGURATION_CHANGED',msg:'cockpitConfigurationChanged'}}});
  const result=structuredClone(fixture);result.requestId=q.requestId;result.snapshotId='controlled-'+requests.length;
  result.context={...result.context,project:'testproject',configurationToken:'a'.repeat(64),reportScope:q.reportScope,focusCategoryId:q.focusCategoryId};
  if(q.time.preset==='custom')result.context.time={...q.time,from:q.time.from!,to:q.time.to!};
  if(q.asOf)result.context.asOf=q.asOf;
  if(q.comparison?.mode==='custom')result.context.comparison=q.comparison;
  result.modules=Object.fromEntries(q.modules.map(m=>[m,result.modules[m]||{status:'unavailable'}]));
  return route.fulfill({json:{ok:true,data:result}});
 });
 await page.goto('/#/cockpit?project=testproject');
 await expect(page.locator('.cockpit-number')).toHaveText('300 kWh');expect(requests).toHaveLength(1);
 expect(requests[0].modules).toEqual(['kpis','trend','issues','space']);
 const zh=language==='zh-CN';
 await page.getByRole('tab',{name:zh?'时间':'Time',exact:true}).click();
 await expect(page.locator('[data-view-snapshot]')).toHaveAttribute('data-view-snapshot','controlled-2');expect(requests).toHaveLength(2);
 await page.getByRole('button',{name:zh?'打开日均用量报告':'Open average daily usage report',exact:true}).click();
 await expect(page.locator('.report-surface')).toBeVisible();
 await page.getByRole('button',{name:zh?'返回驾驶舱':'Return to cockpit',exact:true}).click();
 await expect(page.locator('.cockpit-number')).toHaveText('300 kWh');
 await expect(page.locator('[data-view-snapshot]')).toHaveAttribute('data-view-snapshot','controlled-2');
 expect(requests).toHaveLength(3);expect(requests[2].modules).toEqual(['kpis','trend','issues','space']);
 expect(requests[2].asOf).toBe(fixture.context.asOf);
 expect(requests[1].modules).toEqual(['time']);expect(requests[1].asOf).toBe(fixture.context.asOf);
 expect(requests[1].expectedConfigurationToken).toBe('a'.repeat(64));
 await page.getByRole('tab',{name:zh?'空间':'Space',exact:true}).click();
 await page.getByRole('tab',{name:zh?'时间':'Time',exact:true}).click();
 await expect(page.locator('[data-view-snapshot]')).toHaveAttribute('data-view-snapshot','controlled-2');expect(requests).toHaveLength(2);
 await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
 await page.screenshot({path:testInfo.outputPath('lazy-time-'+language+'.png'),fullPage:true});
 await page.setViewportSize({width:1440,height:1000});
 await openCockpitActions(page);await page.getByRole('button',{name:zh?'完整汇报与导出':'Complete report and export',exact:true}).click();
 await expect(page.getByRole('dialog')).toBeVisible();expect(requests).toHaveLength(4);expect(requests[3].modules).toHaveLength(9);
 await expect(page.getByRole('dialog')).toContainText('controlled-4');
 await page.getByRole('button',{name:zh?'关闭汇报':'Close report',exact:true}).click();
 await expect(page.locator('.cockpit-snapshot')).toHaveAttribute('data-cockpit-snapshot','controlled-3');
 fail=true;await page.getByRole('tab',{name:zh?'计量平衡':'Metering balance',exact:true}).click();
 await expect(page.locator('.cockpit-page .ant-alert-warning')).toContainText(zh?'配置已变化':'Configuration changed');
 await expect(page.locator('.cockpit-number')).toHaveText('300 kWh');expect(requests).toHaveLength(5);
 fail=false;await page.locator('.cockpit-query-submit').click();
 await expect(page.locator('[data-view-snapshot]')).toHaveAttribute('data-view-snapshot','controlled-7');
 expect(requests).toHaveLength(7);expect(requests[5].asOf).toBeUndefined();expect(requests[5].modules).toEqual(['kpis','trend','issues','space']);expect(requests[6].modules).toEqual(['balance']);
 expect(state.requests.filter(r=>r.path==='report')).toHaveLength(0);
});
