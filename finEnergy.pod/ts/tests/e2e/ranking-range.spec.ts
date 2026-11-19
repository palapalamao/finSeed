import {test,expect} from '@playwright/test';
import {createRequire} from 'node:module';
import {installTransport,openView,resultFor,testRecords} from './fixtures';
import type {ReportRequest} from '../../src/types';

const from='2026-10-24T01:45:00+08:00',to='2026-10-24T02:18:20+08:00';
const {Workbook}=createRequire(import.meta.url)('exceljs');
const requested:ReportRequest={kind:'ranking',dimension:'space',nodeIds:['meter1'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-24T03:00:00+08:00',period:'hour',metric:'energy',perArea:false};
for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`ranking range ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('keeps requested times while disclosing legacy server coverage',async({page})=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  await installTransport(page,{records:[...testRecords(),{id:'range-template',kind:'template',name:'宽范围排名',request:requested}]});
  const requests:ReportRequest[]=[];
  await page.route('**/v1/report',route=>{
   const request=route.request().postDataJSON() as ReportRequest;requests.push(request);
   return route.fulfill({json:{ok:true,data:{...resultFor({...request,from,to}),...(request.from!==from||request.to!==to?{rangeAdjustment:{status:'adjusted',requestedFrom:request.from,requestedTo:request.to}}:{})}}});
  });
  await openView(page,'ranking');
  await page.locator('.template-select').getByRole('combobox').click();
  await page.locator('.ant-select-dropdown:visible').getByText('宽范围排名',{exact:true}).click();
  const query=page.getByRole('button',{name:zh?'查询':'Query',exact:true});await query.click();
  const notice=page.locator('.report-range-adjustment');
  await expect(notice).toContainText(zh?'所选查询范围保持不变':'selected query range is unchanged');
  await expect(notice).toContainText(from);await expect(notice).toContainText(to);
  const inputs=page.locator('.filter-period input');await expect(inputs.nth(0)).toHaveValue('2026-10-24 00:00:00');await expect(inputs.nth(1)).toHaveValue('2026-10-24 03:00:00');
  await expect(page.locator('.print-heading')).toContainText(from);await expect(page.locator('.report-chart canvas').first()).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
  await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).click();
  const download=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();
  const workbook=new Workbook();await workbook.xlsx.readFile((await (await download).path())!);
  const metadata=workbook.worksheets[0].getSheetValues().flatMap(row=>Array.isArray(row)?row:[]);
  expect(metadata).toContain(from);expect(metadata).toContain(to);expect(metadata).toContain(requested.from);expect(metadata).toContain(requested.to);
  await query.click();await expect.poll(()=>requests.length).toBe(2);
  expect(requests[0]).toMatchObject(requested);expect(requests[1]).toMatchObject(requested);
  await expect(notice).toBeVisible();
 });
 test('explains when there is no shared interval and keeps the selected times',async({page})=>{
  const zh=locale==='zh-CN';await installTransport(page,{records:[...testRecords(),{id:'range-template',kind:'template',name:'宽范围排名',request:requested}]});
  await page.route('**/v1/report',route=>route.fulfill({json:{ok:true,data:{...resultFor(requested,true),rangeAdjustment:{status:'unavailable',requestedFrom:requested.from,requestedTo:requested.to}}}}));
  await openView(page,'ranking');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('宽范围排名',{exact:true}).click();await page.getByRole('button',{name:zh?'查询':'Query',exact:true}).click();
  await expect(page.locator('.report-range-adjustment')).toContainText(zh?'所选查询范围保持不变':'selected query range is unchanged');
  await expect(page.locator('.filter-period input').first()).toHaveValue('2026-10-24 00:00:00');
 });
});
