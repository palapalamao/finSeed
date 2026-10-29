import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,resultFor,testRecords} from './fixtures';
import type {ReportRequest} from '../../src/types';

for(const language of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`Report diagnostics ${language} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale:language,viewport:mobile?{width:390,height:844}:{width:1440,height:1000}});
 test('keeps charts ahead of collapsed diagnostics while preserving details and printing',async({page},testInfo)=>{
  const zh=language==='zh-CN';const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
  const request:ReportRequest={kind:'profile',dimension:'metering',nodeIds:['meter1'],from:'2026-10-01T00:00:00+08:00',to:'2026-10-03T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
  await installTransport(page,{records:[...testRecords(),{id:'diagnostics-template',kind:'template',name:'Diagnostics example',request}]});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
   const current=route.request().postDataJSON() as ReportRequest;const result=resultFor(current);
   result.warnings=Array.from({length:16},(_,index)=>`Meter ${index+1}: missing`);
   result.extra={usageBasis:'knownUsage',cleaning:Array.from({length:8},(_,index)=>({pointId:`point-${index+1}`,profileName:'cleanDirtyData',profileVersion:2,summary:{rawCount:39737,filteredCount:21,coverage:.1522},parameters:{maximum:1000},details:[{source:'Sample filtered',value:null}]}))};
   await route.fulfill({json:{ok:true,data:result}});
  });
  await openView(page,'profile');
  await page.locator('.template-select').getByRole('combobox').click();
  await page.locator('.ant-select-dropdown:visible').getByText('Diagnostics example',{exact:true}).click();
  const query=page.getByRole('button',{name:zh?/查\s*询/:/^Query$/});await query.click();
  const warnings=page.locator('.report-notices');const cleaning=page.locator('.cleaning-report-summary');
  await expect(warnings.locator(':scope > summary')).toHaveText(zh?'数据提示（16 条）':'Data notices (16)');
  await expect(cleaning.locator(':scope > summary')).toHaveText(zh?'数据清洗与覆盖情况（8 项）':'Data cleaning and coverage (8 entries)');
  await expect(warnings).not.toHaveAttribute('open');await expect(cleaning).not.toHaveAttribute('open');
  await expect(warnings.locator('.report-warning').first()).toBeHidden();await expect(cleaning.locator('.cleaning-report-snapshot').first()).toBeHidden();
  await expect(page.locator('.report-chart canvas')).toHaveCount(1);
  const warningBox=(await warnings.boundingBox())!;const cleaningBox=(await cleaning.boundingBox())!;const overviewBox=(await page.locator('.profile-overview').boundingBox())!;
  expect(cleaningBox.y+cleaningBox.height-warningBox.y).toBeLessThan(135);expect(overviewBox.y).toBeGreaterThan(cleaningBox.y);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.locator('.report-surface').screenshot({path:testInfo.outputPath('chart-first.png')});
  await warnings.locator(':scope > summary').press('Enter');await expect(warnings.getByText(/Meter 16/)).toBeVisible();
  await warnings.locator(':scope > summary').press('Enter');await expect(warnings).not.toHaveAttribute('open');
  await cleaning.locator(':scope > summary').press('Space');await expect(cleaning.locator('.cleaning-report-snapshot')).toHaveCount(8);await expect(cleaning.locator('.cleaning-report-snapshot').last()).toBeVisible();
  await cleaning.locator('.cleaning-report-snapshot details > summary').first().click();await expect(cleaning.getByText('Sample filtered',{exact:true})).toHaveCount(8);await expect(cleaning.getByText('Sample filtered',{exact:true}).first()).toBeVisible();
  await cleaning.locator(':scope > summary').press('Space');
  await page.evaluate(()=>window.dispatchEvent(new Event('beforeprint')));await expect(warnings).toHaveAttribute('open');await expect(cleaning).toHaveAttribute('open');await expect(cleaning.getByText('Sample filtered',{exact:true}).last()).toBeVisible();
  await page.evaluate(()=>window.dispatchEvent(new Event('afterprint')));await expect(warnings).not.toHaveAttribute('open');await expect(cleaning).not.toHaveAttribute('open');
  if(!mobile){
   await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).hover();const downloadEvent=page.waitForEvent('download');
   await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();const download=await downloadEvent;const path=testInfo.outputPath('diagnostics.xlsx');await download.saveAs(path);
   const zip=await JSZip.loadAsync(await readFile(path));const strings=await zip.file('xl/sharedStrings.xml')!.async('string');expect(strings).toContain('Meter 16');expect(strings).toContain('cleanDirtyData');
  }
  await warnings.locator(':scope > summary').click();await cleaning.locator(':scope > summary').click();await query.click();
  await expect(warnings).not.toHaveAttribute('open');await expect(cleaning).not.toHaveAttribute('open');expect(errors).toEqual([]);
 });
});
