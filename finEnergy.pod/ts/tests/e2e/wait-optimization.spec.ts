import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {FinEnergyRecord} from '../../src/types';

for(const language of ['zh-CN','en-US']){
 test('light catalog is single flight and tasks alone request operational details '+language,async({page})=>{
  const calls:string[]=[];page.on('request',request=>{if(new URL(request.url()).pathname.endsWith('/catalog'))calls.push(request.url());});
  await installTransport(page,{userLocale:language,records:[{id:'job',kind:'job',name:'Scheduled scan',action:'scanAlarms',enabled:true}]});
  await openView(page,'profile');await expect.poll(()=>calls.length).toBe(1);expect(calls[0]).toContain('mode=analysis');
  await page.evaluate(()=>{location.hash='/otherSettings?project=testproject';});
  await expect(page.getByRole('heading',{name:language==='zh-CN'?'其他配置':'Other settings',exact:true})).toBeVisible();expect(calls).toHaveLength(1);
  await page.evaluate(()=>{location.hash='/tasks?project=testproject';});
  await expect.poll(()=>calls.length).toBe(2);expect(calls[1]).not.toContain('mode=analysis');
  await expect(page.getByText('Scheduled scan',{exact:true})).toBeVisible();
  await page.evaluate(()=>{location.hash='/categories?project=testproject';});
  await expect(page.locator('.management h2').first()).toBeVisible();
  expect(calls).toHaveLength(2);
 });
 test('alarm list pages summaries and reads complete hours only on expansion '+language,async({page},testInfo)=>{
  const alarms:FinEnergyRecord[]=Array.from({length:65},(_,i)=>({id:'event'+i,mod:'m1',name:'Event '+i,kind:'alarm',nodeId:'meter1',categoryId:'cat1',state:'open',ts:'2026-11-01T00:00:00Z',limit:10,value:20,hourCount:2,hours:[{ts:'2026-11-01T00:00:00Z',value:20,limit:10,unit:'kWh',quality:'ok',priorAckNote:'Full original evidence'},{ts:'2026-11-01T01:00:00Z',value:30,limit:10,unit:'kWh',quality:'ok'}]}));
  const state=await installTransport(page,{userLocale:language,alarms});await openView(page,'messages');
  const main=page.locator('.message-center .management > .ant-table-wrapper').first();
  await expect(main.locator('tbody > tr.ant-table-row')).toHaveCount(30);
  expect(state.requests.filter(r=>r.path==='alarms/detail')).toHaveLength(0);expect(state.requests.filter(r=>r.path==='alarms')).toHaveLength(0);
  await main.locator('.ant-table-row-expand-icon').first().click();await expect(page.getByText('Full original evidence',{exact:true})).toBeVisible();
  expect(state.requests.filter(r=>r.path==='alarms/detail')).toHaveLength(1);
  await main.locator('.ant-table-row-expand-icon-expanded').first().click();await main.locator('.ant-pagination-next').first().click();
  await expect.poll(()=>state.requests.filter(r=>r.path==='alarms/page').length).toBe(2);
  await expect(main.locator('tbody > tr.ant-table-row')).toHaveCount(30);
  await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('alarm-page-'+language+'.png'),fullPage:true});
 });
}
