import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,testRecords} from './fixtures';
import type {ReportResult,ReportRequest} from '../../src/types';

function largeCoverage():ReportResult{
 const start=Date.parse('2026-10-19T00:00:00+08:00');
 const iso=(seconds:number)=>new Date(start+seconds*1000+8*3600000).toISOString().slice(0,-1)+'+08:00';
 let budget=1000;
 const rows=Array.from({length:168},(_,hour)=>{
  const numeric=hour>=122&&hour<=159,covered=numeric?(hour===122?2400:hour===159?1140:3600):0;
  const count=covered/10,provided=Math.min(budget,count);budget-=provided;
  const intervals=Array.from({length:provided},(_,i)=>({intervalStart:iso(hour*3600+(hour===122?1200:0)+i*10),intervalEnd:iso(hour*3600+(hour===122?1200:0)+(i+1)*10),value:1000/count,valueType:'number',quality:'cleaned'}));
  return {nodeId:'meter1',pointId:'point1',sourceIds:['point1'],unit:'kWh',from:iso(hour*3600),to:iso((hour+1)*3600),knownValue:numeric?1000:null,knownValueType:numeric?'number':'null',knownQuality:numeric?(covered<3600?'filtered':'cleaned'):'missing',coveredSeconds:covered,intervalCount:count,intervals,detailsTruncated:provided<count,intervalStart:numeric?iso(hour*3600+(hour===122?1200:0)):null,intervalEnd:numeric?iso(hour*3600+(hour===122?3600:covered)):null};
 }).reverse();
 const points=Array.from({length:7},(_,day)=>({ts:iso(day*86400),value:null,quality:'incompleteInterval',knownValue:day===5?22000:day===6?16000:null,knownValueType:day<5?'null':'number',knownQuality:day<5?'missing':'filtered',bucketEnd:iso((day+1)*86400),sourceIds:['point1']}));
 return {kind:'profile',from:iso(0),to:iso(168*3600),period:'day',rows:points.map(p=>({...p,nodeId:'meter1',unit:'kWh'})),series:[{id:'meter1|cat1',nodeId:'meter1',categoryId:'cat1',name:'测试总电表',unit:'kWh',points:points as ReportResult['series'][number]['points']}],summary:{totals:[{id:'meter1|cat1',value:null,quality:'incompleteInterval'}],knownTotals:[{id:'meter1|cat1',value:38000,quality:'filtered'}]},warnings:[],extra:{dimension:'metering',knownUsage:{basis:'closedSourceIntervals',detailsTruncated:true,sourceUsage:rows}}};
}
async function prepare(page:Parameters<typeof installTransport>[0],result:ReportResult){
 const request:ReportRequest={kind:'profile',dimension:'metering',nodeIds:['meter1'],from:result.from,to:result.to,period:'day',metric:'energy',perArea:false};
 await installTransport(page,{records:[...testRecords(),{id:'coverage-template',kind:'template',name:'Coverage week',request}]});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',r=>r.fulfill({json:{ok:true,data:result}}));
 await openView(page,'profile');await page.locator('.template-select').getByRole('combobox').press('Enter');await page.locator('.ant-select-dropdown:visible').getByTitle('Coverage week',{exact:true}).click();
 await page.getByRole('button',{name:/查\s*询|Query$/}).click();
}
for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`coverage ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('summarizes a week and exposes sorted bounded detail and readable Excel',async({page},info)=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});await page.clock.setFixedTime(new Date('2026-10-25T15:19:24+08:00'));
  await prepare(page,largeCoverage());
  const panel=page.locator('.usage-coverage');await expect(panel).toBeVisible();expect((await panel.innerText()).length).toBeLessThan(1200);
  await expect(panel).not.toContainText('"sourceUsage"');await expect(panel.locator('.usage-coverage-source')).toHaveCount(1);
  await panel.locator('summary').click();await expect(panel.getByText(zh?'只看缺测与异常':'Show gaps and issues only',{exact:true})).toBeVisible();
  const table=panel.locator('.usage-coverage-period-table');await expect(table).toContainText('2026-10-19 00:00:00');await expect(table).toContainText('2026-10-24 02:00:00');
  await expect(table.locator('tbody.ant-table-tbody > tr.ant-table-row')).toHaveCount(3);
  await panel.getByRole('switch').click();
  await table.locator('tbody.ant-table-tbody > tr.ant-table-row').nth(1).getByRole('button',{name:zh?'展开行':'Expand row',exact:true}).click();
  await expect(panel.locator('.usage-coverage-raw')).toBeVisible();expect(await panel.locator('.usage-coverage-raw tbody > tr.ant-table-row').count()).toBeLessThanOrEqual(10);
  if(mobile)expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  const pending=page.waitForEvent('download');await panel.getByRole('button',{name:zh?'导出覆盖明细':'Export coverage details',exact:true}).click();
  const file=info.outputPath('coverage-details.xlsx');await (await pending).saveAs(file);const zip=await JSZip.loadAsync(await readFile(file));
  const workbook=await zip.file('xl/workbook.xml')!.async('string');expect(workbook).toContain(zh?'原始区间':'Source intervals');expect(workbook).toContain(zh?'覆盖摘要':'Coverage summary');
  const source=await zip.file('xl/worksheets/sheet4.xml')!.async('string'),summary=await zip.file('xl/worksheets/sheet2.xml')!.async('string'),periods=await zip.file('xl/worksheets/sheet3.xml')!.async('string');
  expect(source.match(/<row\b/g)).toHaveLength(1001);expect(summary.match(/<row\b/g)).toHaveLength(2);expect(periods.match(/<row\b/g)!.length).toBeLessThan(15);
  const strings=Array.from((await zip.file('xl/sharedStrings.xml')!.async('string')).matchAll(/<si>([\s\S]*?)<\/si>/g),m=>m[1]);
  const firstTime=periods.match(/<c\b[^>]*r="C2"[^>]*>[\s\S]*?<v>(\d+)<\/v>/)![1];expect(strings[Number(firstTime)]).toContain('2026-10-19');
  await panel.scrollIntoViewIfNeeded();await page.screenshot({path:info.outputPath('coverage-readable.png'),fullPage:true});
 });
});

test('replays the user pasted diagnostic without a giant text block',async({page},info)=>{
 test.skip(!process.env.ENERCUBIX_COVERAGE_REPLAY,'Optional local replay of user-provided report evidence');
 await page.setViewportSize({width:390,height:844});await page.clock.setFixedTime(new Date('2026-10-25T15:19:24+08:00'));
 const result=JSON.parse(await readFile(process.env.ENERCUBIX_COVERAGE_REPLAY!,'utf8')) as ReportResult;await prepare(page,result);
 const panel=page.locator('.usage-coverage');await expect(panel).toBeVisible();expect((await panel.innerText()).length).toBeLessThan(1200);expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
 await panel.scrollIntoViewIfNeeded();await page.screenshot({path:info.outputPath('actual-report-coverage-summary.png'),fullPage:true});
 await panel.locator('summary').click();await page.screenshot({path:info.outputPath('actual-report-coverage-periods.png'),fullPage:true});
});
