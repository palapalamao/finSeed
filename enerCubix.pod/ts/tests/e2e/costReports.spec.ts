import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,checkNode,resultFor} from './fixtures';
import type {ReportRequest,ReportResult} from '../../src/types';

function costResult(request:ReportRequest):ReportResult{
 const result=resultFor(request);
 result.series.forEach(series=>{series.unit='元';series.points.forEach((point,index)=>{point.band=index%2?'valley':'sharp';});});
 result.rows.forEach(row=>row.unit='元');
 if(request.kind==='forecast'){
  (result.extra!.forecasts as Record<string,unknown>[]).forEach(row=>{row.unit='元';row.model='meterSum';});
  return result;
 }
 result.summary={totals:[{id:'meter1',value:null,quality:'incompleteInterval',unit:'元'}],knownTotals:[{id:'meter1',name:'测试分表',value:12,quality:'filtered',unit:'元'}]};
 result.series[0].points[0]={...result.series[0].points[0],value:null,knownValue:12,knownQuality:'filtered'};
 result.rows=[{nodeId:'meter1',value:null,knownValue:12,quality:'incompleteInterval',knownQuality:'filtered',unit:'元',band:'sharp'}];
 result.extra={usageBasis:'knownUsage',loadBands:[{band:'sharp',value:null,knownValue:12,quality:'incompleteInterval',knownQuality:'filtered',unit:'元'}]};
 return result;
}

for(const language of ['zh-CN','en-US'])for(const width of [1440,390])test.describe(`${language} cost ${width}`,()=>{
 test.use({locale:language,viewport:{width,height:900}});
 const zh=language==='zh-CN';
 test('queries and exports an available cost subtotal, retaining four-band labels and frozen request',async({page})=>{
  const state=await installTransport(page,{report:costResult});
  await openView(page,'profile');await checkNode(page);
  await page.getByRole('radio',{name:zh?'费用':'Cost',exact:true}).locator('..').click();
  await page.getByRole('button',{name:zh?/查\s*询/:/Query$/}).click();
  await expect(page.locator('.profile-object-summary').first()).toContainText(zh?'已有费用小计':'Available cost subtotal');
  await expect(page.locator('.profile-object-summary').first()).toContainText('12');
  expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.metric).toBe('cost');
  // A draft metric change must not alter the current report's exported snapshot.
  await page.getByRole('radio',{name:zh?'能耗':'Energy',exact:true}).locator('..').click();
  await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).click();
  const download=page.waitForEvent('download');
  await page.getByText(zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',{exact:true}).click();
  const file=await (await download).path();const zip=await JSZip.loadAsync(await readFile(file!));
  const text=await zip.file('xl/sharedStrings.xml')!.async('string');
  expect(text).toContain(zh?'尖时':'Sharp peak');
  expect(text).toContain(zh?'费用':'Cost');
  expect(state.requests.filter(r=>r.path==='report')).toHaveLength(1);
  expect(await page.locator('body').evaluate(body=>body.scrollWidth<=innerWidth+1)).toBe(true);
 });
 test('offers cost queries for flow and forecast and renders sharp-peak coloring',async({page})=>{
  const state=await installTransport(page,{report:costResult});
  for(const view of ['forecast','daily','energyFlow']){
   await openView(page,view);await checkNode(page);
   await page.getByRole('radio',{name:zh?'费用':'Cost',exact:true}).locator('..').click();
   await page.getByRole('button',{name:zh?/查\s*询/:/Query$/}).click();
   await expect(page.getByRole('button',{name:zh?'导出当前报表':'Export current report'})).toBeVisible();
   expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.metric).toBe('cost');
   if(view==='forecast')await expect(page.locator('.report-surface')).toContainText(zh?'不是账单':'are not bills');
   if(view==='daily'){
    await page.getByRole('radio',{name:zh?'按尖峰谷平配色':'Color by sharp peak / peak / flat / valley',exact:true}).locator('..').click();
    await expect(page.locator('.load-band-legend')).toContainText(zh?'尖时':'Sharp peak');
   }
  }
 });
});
