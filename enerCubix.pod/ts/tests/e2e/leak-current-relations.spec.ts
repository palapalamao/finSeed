import {readFileSync} from 'node:fs';
import JSZip from 'jszip';
import {test,expect} from '@playwright/test';
import {installTransport,openView,closeObjects} from './fixtures';
import {chartOptions} from '../../src/chartOptions';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

// Produced by the real Fantom engine from controlled inputs, with an unknown
// relationship log. This is UI replay evidence, not a live FIN adapter test.
const fixture=JSON.parse(readFileSync(new URL('../fixtures/leak-current-relations.json',import.meta.url),'utf8')) as {request:ReportRequest;records:EnerCubixRecord[];report:ReportResult};

for(const language of ['zh-CN','en-US'])test(`shows October 24 using current relationships in ${language}`,async({page},testInfo)=>{
 const result=structuredClone(fixture.report),request=fixture.request;
 const errors:string[]=[];page.on('pageerror',err=>errors.push(err.message));

 const records=[...fixture.records,{id:'current-template',kind:'template',name:'Current relationships',request}];
 const state=await installTransport(page,{userLocale:language,records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  state.requests.push({path:'report',body:route.request().postDataJSON()});
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'leak');
 await page.locator('.template-select').getByRole('combobox').click();
 await page.locator('.ant-select-dropdown:visible').getByText('Current relationships',{exact:true}).click();
 await closeObjects(page);
 await page.getByRole('button',{name:language==='zh-CN'?/查\s*询/:'Query',exact:true}).click();
 const overview=page.locator('.leak-overview');
 await expect(overview).toContainText(language==='zh-CN'?'关系变更仅作日志':'Relationship changes are audit logs only');
 await expect(overview.locator('.metric-readout').nth(1)).toContainText('559030');
 await expect(overview.locator('.metric-readout').nth(2)).toContainText('-33730');
 await expect(overview.locator('.metric-readout').nth(3)).toContainText('-6.42');
 expect((result.extra?.leakTotals as Record<string,unknown>[])[0]).toMatchObject({difference:null,percentage:null});
 await expect(overview.locator('.report-chart canvas')).toHaveCount(1);
 const options=chartOptions(result);
 const dates=(options.xAxis as {data:string[]}).data;
 const index=dates.findIndex(date=>date.startsWith('2026-10-24'));
 expect(index).toBeGreaterThanOrEqual(0);
 const bars=options.series as {data:{value:number|null}[]}[];
 expect(bars.map(bar=>bar.data[index].value)).toEqual([232908,86071,172082,null]);
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:960});
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(overview.locator('.report-chart canvas')).toBeVisible();
  await overview.screenshot({path:testInfo.outputPath(`current-relations-${language}-${width}.png`)});
 }
 await page.getByRole('button',{name:language==='zh-CN'?'导出当前报表':'Export current report'}).click();
 const pending=page.waitForEvent('download');
 await page.getByRole('menuitem',{name:/Excel/}).click();
 const download=await pending;const path=testInfo.outputPath(download.suggestedFilename());
 await download.saveAs(path);
 const zip=await JSZip.loadAsync(readFileSync(path));
 const strings=await zip.file('xl/sharedStrings.xml')!.async('string');
 expect(strings).toContain(language==='zh-CN'?'当前关系':'Current relationships');
 expect(strings).toContain('258153');
 expect(errors).toEqual([]);
 expect(result).toEqual(fixture.report);
});
