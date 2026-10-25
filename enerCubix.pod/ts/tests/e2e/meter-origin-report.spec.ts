import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

for(const locale of ['zh-CN','en-US'])test.describe(locale,()=>{
 test.use({locale});
 test('keeps meter types visible in profiles and Excel without changing names or the query range',async({page},info)=>{
  const zh=locale==='zh-CN';const request:ReportRequest={kind:'profile',dimension:'metering',nodeIds:['physical','virtual'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-25T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
  const records:EnerCubixRecord[]=[{id:'c',kind:'category',name:'电能',unit:'kWh'},{id:'physical',kind:'totalMeter',name:'真实进线',categoryId:'c',meterOrigin:{type:'physical',reason:'connector',protocol:'modbus',pointId:'p',connectorId:'connector'}},{id:'virtual',kind:'totalMeter',name:'用户虚总表原名',categoryId:'c',autoSum:true},{id:'t',kind:'template',name:'Source types',request}];
  const state=await installTransport(page,{records});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
   const current=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:current as unknown as Record<string,unknown>});
   const result:ReportResult={kind:'profile',from:current.from,to:current.to,period:current.period,series:['physical','virtual'].map((id,i)=>({id,nodeId:id,name:i?'用户虚总表原名':'真实进线',categoryId:'c',unit:'kWh',points:[{ts:current.from,value:25+i,quality:'ok',sourceIds:['p']}]})),rows:['physical','virtual'].map((id,i)=>({nodeId:id,name:i?'用户虚总表原名':'真实进线',categoryId:'c',unit:'kWh',ts:current.from,value:25+i,quality:'ok',sourceIds:['p']})),warnings:[],summary:{}};
   await route.fulfill({json:{ok:true,data:result}});
  });
  await openView(page,'profile');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('Source types',{exact:true}).click();await page.getByRole('button',{name:zh?/查\s*询/:/^Query$/}).click();
  const profiles=page.locator('.profile-summaries');await expect(profiles.getByText(zh?'物理总表':'pTotal Meter',{exact:true})).toBeVisible();await expect(profiles.getByText(zh?'虚拟总表':'vTotal Meter',{exact:true})).toBeVisible();
  await expect(page.locator('.report-chart canvas')).toBeVisible();
  await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).hover();const downloadPromise=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();const download=await downloadPromise,file=info.outputPath('meter-origin.xlsx');await download.saveAs(file);
  const zip=await JSZip.loadAsync(await readFile(file)),strings=await zip.file('xl/sharedStrings.xml')!.async('string');
  expect(strings).toContain('用户虚总表原名');expect(strings).toContain(zh?'虚拟总表':'vTotal Meter');expect(strings).toContain(zh?'物理总表':'pTotal Meter');
  const sent=state.requests.filter(row=>row.path==='report');expect(sent).toHaveLength(1);expect(sent[0].body.from).toBe(request.from);expect(sent[0].body.to).toBe(request.to);
  await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  for(const badge of await profiles.locator('.meter-origin-badge').all()){const box=(await badge.boundingBox())!;expect(box.width).toBeGreaterThan(65);expect(box.height).toBeLessThan(40);}
  await page.screenshot({path:info.outputPath('meter-origin-profile-mobile.png'),fullPage:true});
 });
});
