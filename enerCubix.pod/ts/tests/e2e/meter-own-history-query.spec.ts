import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView} from './fixtures';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';

// Opt-in presentation acceptance using a separately captured, audited FIN result.
// This checks rendering/export of the real query payload; it does not replace live FIN acceptance.
const evidencePath=process.env.ENERCUBIX_QUERY_EVIDENCE;
for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`own stored query ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('renders and exports all native total readings without querying children',async({page},testInfo)=>{
  test.skip(!evidencePath,'Set ENERCUBIX_QUERY_EVIDENCE to the audited candidate query capture.');
  const evidence=JSON.parse(await readFile(evidencePath!,'utf8')) as {request:ReportRequest;result:ReportResult;rawRows:{ts:string;value:number|null;valueType:string}[]};
  const {request,result,rawRows}=evidence;const series=result.series[0],nodeId=request.nodeIds[0],sourceId=series.points[0].sourceIds[0];
  expect(series.points.map(p=>({ts:p.ts,value:p.value,valueType:p.valueType||'number'}))).toEqual(rawRows);
  expect(series.points).toHaveLength(345);expect(series.points[0].value).toBe(35859);expect(series.points.at(-1)?.value).toBe(46617);
  expect(series.points.every(p=>p.sourceIds.length===1&&p.sourceIds[0]===sourceId)).toBe(true);
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
  const templateName='cubeTest · 总电表 · 00:00—01:00';
  const records:EnerCubixRecord[]=[{id:series.categoryId,kind:'category',name:'电能',unit:'kWh'},{id:nodeId,kind:'totalMeter',name:'总电表',pointId:sourceId,categoryId:series.categoryId,unit:'kWh',autoSum:true,nativeEquip:true,includeInTotals:true},{id:'query-template',kind:'template',name:templateName,request}];
  const state=await installTransport(page,{records,storageModel:'nativeEquip',spaceSource:'fin'});
  await page.route('**/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:[{id:sourceId,name:'电能',equipName:'总电表',unit:'kWh',his:true}],total:1,offset:0,limit:100}}}));
  await page.route('**/v1/report',route=>{state.requests.push({path:'report',body:route.request().postDataJSON()});return route.fulfill({json:{ok:true,data:result}});});
  await openView(page,'trend');
  await page.getByRole('combobox',{name:zh?'报表模板':'Report templates',exact:true}).click();
  await page.locator('.ant-select-dropdown:visible').getByText(templateName,{exact:true}).click();
  await page.getByRole('button',{name:zh?'查询':'Query',exact:true}).click();
  await expect(page.locator('.report-chart canvas')).toBeVisible();
  await expect(page.locator('.report-surface').getByRole('cell',{name:/^35,?859(?:\.00)?$/}).first()).toBeVisible();
  await expect(page.locator('.report-surface').getByRole('cell',{name:/^46,?617(?:\.00)?$/}).first()).toHaveCount(1);
  await expect(page.locator('.cleaning-report-summary')).toHaveCount(0);
  expect(state.requests.filter(call=>call.path==='report')).toHaveLength(1);
  expect(state.requests.find(call=>call.path==='report')?.body).toMatchObject(request);
  expect(state.requests.some(call=>['records','tree/manage','tasks'].includes(call.path))).toBe(false);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.locator('.report-chart').screenshot({path:testInfo.outputPath('own-total-native-query.png')});
  await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).hover();
  const event=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)'}).click();
  const download=await event;const path=testInfo.outputPath('own-total-native-query.xlsx');await download.saveAs(path);
  const zip=await JSZip.loadAsync(await readFile(path));
  const shared=await zip.file('xl/sharedStrings.xml')!.async('string');
  const strings=[...shared.matchAll(/<si>([\s\S]*?)<\/si>/g)].map(item=>[...item[1].matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map(text=>text[1]).join(''));
  const sheet=await zip.file('xl/worksheets/sheet2.xml')!.async('string');
  const detail=[...sheet.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)].map(row=>[...row[1].matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)].map(cell=>{
   const value=cell[2].match(/<v>([\s\S]*?)<\/v>/)?.[1]||'';return /\bt="s"/.test(cell[1])?strings[Number(value)]:value;
  }));
  expect(detail.length).toBe(rawRows.length+1);
  const valueColumn=detail[0].indexOf(zh?'值':'Value');expect(valueColumn).toBeGreaterThanOrEqual(0);
  const exported=detail.slice(1).map(row=>Number(row[valueColumn].replace(/,/g,'')));
  expect(exported).toEqual(rawRows.map(row=>row.value));
  expect(errors).toEqual([]);
 });
});
