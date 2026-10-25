import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,testRecords} from './fixtures';
import type {ReportRequest,ReportResult,ReportPoint} from '../../src/types';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`known consumption ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('keeps available usage visible for hourly, daily and weekly reports and freezes Excel statistics',async({page},testInfo)=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  await page.clock.setFixedTime(new Date('2026-10-25T02:30:00+08:00'));
  const from='2026-10-25T00:00:00+08:00',to='2026-10-25T02:30:00+08:00';
  const base:ReportRequest={kind:'profile',dimension:'metering',nodeIds:['meter1'],from,to,period:'hour',metric:'energy',perArea:false};
  const records=[...testRecords(),...(['hour','day','week'] as const).map(period=>({id:'partial-'+period,kind:'template' as const,name:'Known '+period,request:{...base,period}}))];
  const state=await installTransport(page,{records,canWrite:false});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
   const request=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:request as unknown as Record<string,unknown>});
   const point=(ts:string,value:number|null,quality:string,knownValue:number|null,knownQuality:string,bucketEnd:string):ReportPoint=>({ts,value,quality,knownValue,knownQuality,knownValueType:knownValue===null?'null':'number',bucketEnd,sourceIds:['point1']});
   const points=request.period==='hour'?[point(from,10,'ok',10,'ok','2026-10-25T01:00:00+08:00'),point('2026-10-25T01:00:00+08:00',20,'filtered',20,'filtered','2026-10-25T02:00:00+08:00'),point('2026-10-25T02:00:00+08:00',null,'incompleteInterval',null,'missing','2026-10-25T03:00:00+08:00')]:[point(request.period==='week'?'2026-10-19T00:00:00+08:00':from,null,'incompleteInterval',30,'filtered',request.period==='week'?'2026-10-26T00:00:00+08:00':'2026-10-26T00:00:00+08:00')];
   const result:ReportResult={kind:'profile',from,to,period:request.period,series:[{id:'meter1|cat1',nodeId:'meter1',name:'测试分表',unit:'kWh',categoryId:'cat1',points}],rows:points.map(p=>({nodeId:'meter1',categoryId:'cat1',...p,unit:'kWh'})),summary:{totals:[{id:'meter1|cat1',value:null,quality:'incompleteInterval'}],knownTotals:[{id:'meter1|cat1',value:30,valueType:'number',quality:'filtered'}]},warnings:[]};
   await route.fulfill({json:{ok:true,data:result}});
  });
  await openView(page,'profile');
  for(const period of ['hour','day','week']){
   await page.locator('.template-select').getByRole('combobox').press('Enter');await page.locator('.ant-select-dropdown:visible').getByText('Known '+period,{exact:true}).click();
   await page.getByRole('button',{name:zh?/查\s*询/:/Query$/}).click();
   const card=page.locator('.profile-object-summary');await expect(card.locator('.metric-readout strong')).toContainText('30');
   await expect(card.locator('.profile-stat').nth(0).locator('strong')).toContainText(period==='hour'?'15':'30');
   await expect(card.locator('.profile-stat').nth(1).locator('strong')).toContainText(period==='hour'?'20':'30');
   await expect(card).toContainText(zh?'已有数据平均':'Available-data mean');await expect(card).toContainText(zh?'已有数据最高':'Recorded maximum');
   await expect(page.locator('.profile-chart-block canvas')).toBeVisible();
   if(mobile)expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
   if(period==='hour'){
    await expect(card).toContainText(zh?'完整 1；部分 1；缺测 0；NA 0；未结束 1':'Complete 1; partial 1; missing 0; NA 0; unfinished 1');
    await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).hover();const event=page.waitForEvent('download');
    await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();const download=await event;
    const path=testInfo.outputPath('known-hour.xlsx');await download.saveAs(path);const zip=await JSZip.loadAsync(await readFile(path));
    const text=(await zip.file('xl/sharedStrings.xml')!.async('string')).replaceAll('&quot;','"');
    expect(text).toContain(zh?'已有数据平均":15':'Available-data mean":15');expect(text).toContain(zh?'已有数据最高":20':'Recorded maximum":20');
    expect(text).toContain(zh?'完整区间总量":null':'Complete-period total":null');
   }
  }
  await page.locator('.profile-overview').scrollIntoViewIfNeeded();await page.screenshot({path:testInfo.outputPath('known-usage.png'),fullPage:true});
  expect(state.requests.filter(request=>request.path==='report')).toHaveLength(3);
 });
});
