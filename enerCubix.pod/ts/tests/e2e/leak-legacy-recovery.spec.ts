import {readFileSync} from 'node:fs';
import JSZip from 'jszip';
import {test,expect} from '@playwright/test';
import {installTransport,openView,closeObjects} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

// Actual dated backups plus FIN's existing hourly quantities; aggregate replay
// checks presentation, not raw-history coverage or a production import.
const replay=JSON.parse(readFileSync(new URL('../fixtures/leak-legacy-replay.json',import.meta.url),'utf8')) as {request:ReportRequest;records:EnerCubixRecord[];report:ReportResult};
for(const language of ['zh-CN','en-US'])test(`shows bounded recovered child usage in ${language}`,async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));

 const result=structuredClone(replay.report),request=replay.request;
 const records:EnerCubixRecord[]=[...replay.records,{id:'legacy-template',kind:'template',name:'October 24 recovery',request}];
 const state=await installTransport(page,{userLocale:language,records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  state.requests.push({path:'report',body:route.request().postDataJSON()});
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'leak');
 await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('October 24 recovery',{exact:true}).click();
 await closeObjects(page);await page.getByRole('button',{name:language==='zh-CN'?/查\s*询/:'Query',exact:true}).click();
 const overview=page.locator('.leak-overview');
 await expect(overview).toContainText(language==='zh-CN'?'部分旧关系已按备份恢复':'Some historical relationships were restored from backups');
 await expect(overview.locator('.metric-readout').nth(0)).toContainText(/232[ ,]?908/);
 await expect(overview.locator('.metric-readout').nth(1)).toContainText(/258[ ,]?153/);
 await expect(overview.locator('.metric-readout').nth(2)).toContainText('—');
 await expect(overview.locator('.report-chart canvas')).toHaveCount(1);
 const sent=state.requests.filter(r=>r.path==='report').at(-1)!.body;
 expect(sent.from).toBe(request.from);expect(sent.to).toBe(request.to);
 await page.getByRole('button',{name:language==='zh-CN'?'导出当前报表':'Export current report'}).hover();
 const downloadPromise=page.waitForEvent('download');await page.getByRole('menuitem',{name:language==='zh-CN'?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();
 const download=await downloadPromise,file=testInfo.outputPath('recovered-leak.xlsx');await download.saveAs(file);
 const zip=await JSZip.loadAsync(readFileSync(file)),strings=await zip.file('xl/sharedStrings.xml')!.async('string');
 expect(strings).toContain(request.from);expect(strings).toContain(request.to);expect(strings).toContain('258153');
 expect(strings).toContain(language==='zh-CN'?'按旧备份恢复':'Restored from historical backups');
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:960});
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(overview.locator('.report-chart canvas')).toBeVisible();
  await overview.screenshot({path:testInfo.outputPath(`legacy-recovery-${language}-${width}.png`)});
 }
 expect(errors).toEqual([]);expect(result).toEqual(replay.report);
});
