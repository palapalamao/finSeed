import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,testRecords} from './fixtures';
import type {ReportRequest,ReportResult} from '../../src/types';

async function setup(page:Page,language:string){
 const from='2026-09-01T00:00:00Z',to='2026-09-15T00:00:00Z';
 const request:ReportRequest={kind:'profile',dimension:'metering',nodeIds:['meter1'],from,to,period:'hour',metric:'energy',perArea:false};
 const points=Array.from({length:325},(_,i)=>({ts:new Date(Date.parse(from)+i*3600000).toISOString(),value:i+1,quality:'ok',sourceIds:['point1']}));
 const report=(q:ReportRequest):ReportResult=>({kind:'profile',from:q.from,to:q.to,asOf:q.asOf||q.to,period:'hour',warnings:[],summary:{},series:[{id:'meter1|cat1',nodeId:'meter1',name:'Meter series',categoryId:'cat1',unit:'kWh',points}],rows:points.map((point,i)=>({...point,id:'row-'+i,name:'Proof-'+i,nodeId:'meter1',categoryId:'cat1',unit:'kWh'})),extra:{details:points.map((point,i)=>({id:'detail-'+i,name:'Detail-'+i,value:point.value}))}});
 const state=await installTransport(page,{userLocale:language,records:[...testRecords(),{id:'large-template',kind:'template',name:'325 row profile',request}],report});
 await openView(page,'profile');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('325 row profile',{exact:true}).click();
 await page.locator('.filter-actions button').filter({has:page.locator('.anticon-search')}).click();await expect(page.locator('.report-surface')).toBeVisible();
 return state;
}

for(const language of ['zh-CN','en-US']){
 test('325 rows remain browsable and native printing synchronously renders every row '+language,async({page},testInfo)=>{
  const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));const state=await setup(page,language);
  const stats=page.locator('.report-details > [data-report-table-rows="325"]').last(),quality=page.locator('.quality-details > [data-report-table-rows="325"]');
  await page.locator('.report-details > summary').click();await page.locator('.quality-details > summary').click();
  await expect(stats.locator('tbody > tr.ant-table-row')).toHaveCount(100);await expect(quality.locator('tbody > tr.ant-table-row')).toHaveCount(100);
  await stats.locator('.ant-pagination-item-4').click();await expect(stats.getByText('Proof-324',{exact:true})).toBeVisible();
  await quality.locator('.ant-pagination-item-4').click();await expect(quality.locator('tbody > tr.ant-table-row')).toHaveCount(25);
  const counts=await page.evaluate(()=>{window.dispatchEvent(new Event('beforeprint'));return [...document.querySelectorAll('[data-report-table-rows="325"]')].map(node=>({mode:node.getAttribute('data-report-table-mode'),rows:node.querySelectorAll('tbody > tr.ant-table-row').length,pages:node.querySelectorAll('.ant-pagination').length}));});
  expect(counts).toHaveLength(3);expect(counts.every(item=>item.mode==='document'&&item.rows===325&&item.pages===0)).toBe(true);
  await expect(stats.getByText('Proof-324',{exact:true})).toBeVisible();
  // The PDF uses the same native beforeprint path; validate the real file later.
  await page.pdf({path:testInfo.outputPath('native-full-'+language+'.pdf'),format:'A4',printBackground:true});
  await page.evaluate(()=>window.dispatchEvent(new Event('afterprint')));
  await expect(stats.locator('tbody > tr.ant-table-row')).toHaveCount(25);await expect(stats.getByText('Proof-324',{exact:true})).toBeVisible();
  await expect(quality.locator('tbody > tr.ant-table-row')).toHaveCount(25);
  expect(state.requests.filter(request=>request.path==='report')).toHaveLength(1);expect(errors).toEqual([]);
  await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('screen-last-page-'+language+'.png'),fullPage:true});
 });
 test('Excel and Word retain row 325 without expanding screen tables '+language,async({page},testInfo)=>{
  await setup(page,language);const zh=language==='zh-CN';
  for(const [label,extension,entry] of [[zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)','xlsx','xl/sharedStrings.xml'],[zh?'Word 文档 (.docx)':'Word document (.docx)','docx','word/document.xml']]){
   await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).hover();const download=page.waitForEvent('download');await page.getByRole('menuitem',{name:label,exact:true}).click();
   const file=await download,path=testInfo.outputPath('all-rows.'+extension);await file.saveAs(path);const zip=await JSZip.loadAsync(await readFile(path));expect(await zip.file(entry)!.async('string')).toContain('Proof-324');
   await expect(page.locator('[data-report-table-mode="document"]')).toHaveCount(0);
  }
 });
}
