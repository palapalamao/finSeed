import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

for(const locale of ['zh-CN','en-US'])test.describe(locale,()=>{
 test.use({locale});
 test('shows a missing object selection as a red blocking error without sending a query',async({page})=>{
  const state=await installTransport(page);await openView(page,'profile');
  await page.getByRole('button',{name:locale==='zh-CN'?/查\s*询/:/^Query$/}).click();
  await expect(page.locator('.ant-alert-error')).toContainText(locale==='zh-CN'?'请先选择分析对象':'Select analysis objects first');
  expect(await page.locator('.ant-alert-error').evaluate(el=>getComputedStyle(el).backgroundColor)).toBe('rgb(255, 242, 240)');
  expect(state.requests.some(row=>row.path==='report')).toBe(false);
 });
 test('shows blocking selection errors in red and incomplete data warnings in yellow',async({page},testInfo)=>{
  const zh=locale==='zh-CN',warning=zh?'测试点：部分数据缺测':'Test point: some readings missing';
  const request:ReportRequest={kind:'proportion',dimension:'metering',nodeIds:['main','child'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-25T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
  const records:EnerCubixRecord[]=[{id:'c',kind:'category',name:'电能',unit:'kWh'},{id:'main',kind:'totalMeter',name:'测试主表',categoryId:'c',autoSum:true},{id:'child',kind:'meter',name:'测试分表',categoryId:'c',meterParentId:'main'},{id:'t',kind:'template',name:'Overlap test',request}];
  const state=await installTransport(page,{records});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
   const current=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:current as unknown as Record<string,unknown>});
   const result:ReportResult={kind:'proportion',from:current.from,to:current.to,period:current.period,series:['main','child'].map(id=>({id,nodeId:id,name:id==='main'?'测试主表':'测试分表',unit:'kWh',points:[{ts:current.from,value:10,quality:'filtered',sourceIds:['p']}]})),rows:['main','child'].map(id=>({nodeId:id,name:id==='main'?'测试主表':'测试分表',value:10,percentage:null,percentageBasis:'overlappingScopes',unit:'kWh'})),warnings:[warning],summary:{}};
   await route.fulfill({json:{ok:true,data:result}});
  });
  await openView(page,'proportion');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('Overlap test',{exact:true}).click();
  await page.getByRole('button',{name:zh?/查\s*询/:/^Query$/}).click();
  const error=page.locator('.ant-alert-error').filter({hasText:zh?'取消总表':'deselect the parent meter'}),warn=page.locator('.ant-alert-warning').filter({hasText:warning});
  await expect(error).toBeVisible();await expect(warn).toBeVisible();
  expect(await error.evaluate(el=>getComputedStyle(el).backgroundColor)).toBe('rgb(255, 242, 240)');
  expect(await warn.evaluate(el=>getComputedStyle(el).backgroundColor)).toBe('rgb(255, 251, 230)');
  await page.screenshot({path:testInfo.outputPath('error-red-warning-yellow.png'),fullPage:true});
  const sent=state.requests.findLast(row=>row.path==='report')!.body;expect(sent.from).toBe(request.from);expect(sent.to).toBe(request.to);
 });
});
