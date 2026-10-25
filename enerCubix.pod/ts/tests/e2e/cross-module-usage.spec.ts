import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {installTransport,openView} from './fixtures';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';

const fixture=JSON.parse(readFileSync(new URL('../../../../out/cross-module-usage/ui-fixtures.json',import.meta.url),'utf8')) as {records:EnerCubixRecord[];requests:Record<string,ReportRequest>;reports:Record<string,ReportResult>};
const {Workbook}=createRequire(import.meta.url)('exceljs');
for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`shared usage ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('keeps range and cutoff across modules and renders known quantities in charts, tables and workbook',async({page},testInfo)=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  await page.clock.setFixedTime(new Date('2026-10-20T02:10:00+08:00'));
  await installTransport(page,{records:[...fixture.records,{id:'cross-template',kind:'template',name:'Cross module fixed range',request:fixture.requests.profile}]});
  const requests:ReportRequest[]=[];
  await page.route('**/v1/report',route=>{const request=route.request().postDataJSON() as ReportRequest;requests.push(request);return route.fulfill({json:{ok:true,data:fixture.reports[request.kind]}});});
  await openView(page,'profile');
  await page.locator('.template-select').getByRole('combobox').click();
  await page.locator('.ant-select-dropdown:visible').getByText('Cross module fixed range',{exact:true}).click();
  const query=page.getByRole('button',{name:zh?'查询':'Query',exact:true});await query.click();
  await expect(page.locator('.report-chart canvas').first()).toBeVisible();
  for(const kind of ['ranking','proportion','utility','daily','comparison','primary','energyFlow','dashboard']){
   const before=requests.length;await page.bringToFront();await page.evaluate(kind=>{location.hash=`#/${kind}?project=testproject`;},kind);
   await expect(page.locator('.content-frame')).toBeVisible();
   if(!['dashboard','energyFlow'].includes(kind))await query.click();
   await expect.poll(()=>requests.length).toBeGreaterThan(before);
   await expect.poll(()=>requests.at(-1)?.kind).toBe(kind);
   const request=requests.at(-1)!;
   expect(request.from,kind).toBe(fixture.requests.profile.from);expect(request.to,kind).toBe(fixture.requests.profile.to);expect(request.asOf,kind).toBe(fixture.requests.profile.asOf);
   expect(request.nodeIds,kind).toEqual(['meter1']);
   await expect(page.locator('.print-heading')).toContainText(fixture.requests.profile.from);
   if(kind==='energyFlow')await expect(page.locator('.energy-flow-table')).toContainText('30');
   else await expect(page.locator('.report-chart canvas').first()).toBeVisible();
   if(['ranking','proportion','comparison'].includes(kind)){
    await expect(page.locator('.report-surface')).toContainText('30');
    await page.bringToFront();await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).click();
    const downloaded=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();
    const book=new Workbook();await book.xlsx.readFile((await (await downloaded).path())!);
    const values=book.worksheets.flatMap((sheet:any)=>sheet.getSheetValues().flatMap((row:unknown)=>Array.isArray(row)?row:[]));
    const atoms=(value:unknown):unknown[]=>typeof value==='object'&&value!==null?Object.values(value).flatMap(atoms):[value];const decoded=values.flatMap((value:unknown)=>{if(typeof value==='string'&&value.startsWith('{')){try{return atoms(JSON.parse(value));}catch{}}return [value];});expect(decoded.map(String)).toContain('30');expect(values).toContain(fixture.requests.profile.from);expect(values).toContain(fixture.requests.profile.to);expect(values).toContain(fixture.requests.profile.asOf);
   }
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),kind).toBe(true);
  }
  await page.screenshot({path:testInfo.outputPath('dashboard.png'),fullPage:true});
 });
});
