import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView} from './fixtures';
import type {ReportRequest,ReportResult,FinEnergyRecord} from '../../src/types';

async function setup(page:Page,language='zh-CN',preview=true){
 const request:ReportRequest={kind:'profile',dimension:'space',spaceSource:'fin',nodeIds:['f1','f2'],from:'2026-09-01T00:00:00+08:00',to:'2026-10-01T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
 const records:FinEnergyRecord[]=[{id:'electric',kind:'category',name:'Electricity',unit:'kWh'},{id:'site',kind:'space',name:'Campus',nativeSourceKind:'site'},
  ...[1,2].flatMap(i=>[{id:'f'+i,kind:'space' as const,name:'Floor '+i,parentId:'site',nativeSourceKind:'floor'},{id:'m'+i,kind:'totalMeter' as const,name:'Main '+i,nativeSpaceId:'f'+i,pointId:'point'+i,categoryId:'electric',unit:'kWh'}]),
  {id:'profile-template',kind:'template',name:'September daily profile',request}];
 const state=await installTransport(page,{records,spaceSource:'fin',userLocale:language});
 const control={failFull:false,backfill:true,increment:2,fullCalls:0,chartCalls:0,delayNames:false};
 const stamp=(instant:number)=>new Date(instant+8*3600000).toISOString().replace('Z','+08:00');
 const build=(q:ReportRequest,full:boolean):ReportResult=>{
  const from=Date.parse(q.from);const series=[1,2].map(i=>({id:'f'+i+'|electric',nodeId:'f'+i,name:'Floor '+i,categoryId:'electric',unit:'kWh',points:Array.from({length:30},(_,d)=>({ts:stamp(from+d*86400000),bucketEnd:stamp(from+(d+1)*86400000),value:i*10+(full&&control.backfill&&i===1&&d===0?control.increment:0),knownValue:i*10+(full&&control.backfill&&i===1&&d===0?control.increment:0),valueType:'number' as const,knownValueType:'number' as const,quality:'ok',knownQuality:'ok',sourceIds:[control.delayNames&&full?'slow-point':'point'+i]}))}));
  const totals=series.map(s=>({id:s.id,name:s.name,categoryId:'electric',unit:'kWh',quality:'ok',value:s.points.reduce((n,p)=>n+p.value,0)}));
  return {kind:'profile',from:q.from,to:q.to,asOf:q.asOf||q.to,period:'day',series,rows:series.flatMap(s=>s.points.map(p=>({...p,nodeId:s.nodeId,name:s.name,categoryId:'electric',unit:'kWh'}))),summary:{totals},warnings:[],extra:{usageBasis:'knownUsage',...(full?{details:[{scopeId:'f1',nodeId:'m1',name:'Full source diagnostics',categoryId:'electric',value:totals[0].value,quality:'ok',sourceIds:['point1']}],cleaning:[{pointId:'point1',sourceIds:['point1'],summary:{coverage:1},details:[]}]}:{profileDelivery:{mode:'chart',diagnostics:'deferred',snapshotId:'chart-'+control.chartCalls,sourceCount:2,phaseMs:{total:1}}})}};
 };
 await page.route('**/api/testproject/ext/finEnergy/v1/report',async route=>{
  const q=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:q as unknown as Record<string,unknown>});
  const full=q.responseMode==='full'||!preview;if(full)control.fullCalls++;else control.chartCalls++;
  if(full&&control.failFull){await route.fulfill({status:500,json:{ok:false,error:{code:'HISTORY_READ_ERROR',msg:'Full read failed'}}});return;}
  await route.fulfill({json:{ok:true,data:build(q,full)}});
 });
 await openView(page,'profile');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('September daily profile',{exact:true}).click();
 await page.locator('.filter-actions button').filter({has:page.locator('.anticon-search')}).click();await expect(page.locator(preview?'.report-profile-first':'.cleaning-report-summary')).toBeVisible();await expect(page.locator('.profile-overview .report-chart canvas')).toHaveCount(1);
 return {control,state};
}

test('a normal profile query returns the complete report in its first request',async({page})=>{
 const {control,state}=await setup(page,'zh-CN',false);
 expect(control.fullCalls).toBe(1);expect(control.chartCalls).toBe(0);
 expect(state.requests.filter(r=>r.path==='report')[0].body.responseMode).toBeUndefined();
 await expect(page.locator('.report-profile-first')).toHaveCount(0);
 await expect(page.locator('.report-surface')).toHaveAttribute('data-report-stage','full');
 await expect.poll(async()=>page.evaluate(()=>performance.getEntriesByName('finenergy.query.operation').some(entry=>entry instanceof PerformanceMeasure&&entry.detail.outcome==='complete'))).toBe(true);
});

for(const language of ['zh-CN','en-US']){
 test('first chart is on demand and replaces the whole snapshot in '+language,async({page},testInfo)=>{
  const {control,state}=await setup(page,language);expect(control.chartCalls).toBe(1);expect(control.fullCalls).toBe(0);
  await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('300');
  await page.screenshot({path:testInfo.outputPath('first-chart-'+language+'.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:testInfo.outputPath('first-chart-mobile-'+language+'.png'),fullPage:true});await page.setViewportSize({width:1440,height:1000});
  await page.locator('label').filter({has:page.getByRole('radio',{name:language==='zh-CN'?'折线图':'Line chart',exact:true})}).click();
  expect(control.fullCalls).toBe(0);
  await page.getByRole('button',{name:language==='zh-CN'?'查看完整诊断':'Read full diagnostics',exact:true}).click();
  await expect(page.locator('.report-profile-first')).toHaveCount(0);await expect(page.locator('.report-profile-rebuilt')).toBeVisible();expect(control.fullCalls).toBe(1);
  await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('302');
  await expect(page.locator('.cleaning-report-summary')).toBeVisible();expect(state.requests.filter(r=>r.path==='report')[1].body.asOf).toBe('2026-10-01T00:00:00+08:00');
  await page.screenshot({path:testInfo.outputPath('full-rebuilt-'+language+'.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('mobile-'+language+'.png'),fullPage:true});
 });
 test('export waits for full data and exports the replacement, '+language,async({page},testInfo)=>{
  const {control}=await setup(page,language);await page.getByRole('button',{name:language==='zh-CN'?'导出当前报表':'Export current report'}).hover();
  const download=page.waitForEvent('download');await page.getByRole('menuitem',{name:language==='zh-CN'?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();
  const file=await download;const path=testInfo.outputPath('rebuilt.xlsx');await file.saveAs(path);const zip=await JSZip.loadAsync(await readFile(path));const strings=await zip.file('xl/sharedStrings.xml')!.async('string');
  expect(control.fullCalls).toBe(1);expect(strings).toContain('Full source diagnostics');expect(strings).not.toContain('chart-1');
  await expect(page.locator('.report-profile-rebuilt')).toBeVisible();await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('302');
 });
}

test('failed full read preserves first chart and allows a later retry',async({page})=>{
 const {control}=await setup(page);control.failFull=true;await page.getByRole('button',{name:'查看完整诊断',exact:true}).click();
 await expect(page.locator('.report-profile-first')).toBeVisible();await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('300');await expect(page.locator('.report-profile-rebuilt')).toHaveCount(0);
 await expect(page.locator('.report-profile-first .ant-btn')).not.toHaveClass(/ant-btn-loading/);control.failFull=false;
 await page.getByRole('button',{name:'查看完整诊断'}).click();await expect(page.locator('.report-profile-rebuilt')).toBeVisible();expect(control.fullCalls).toBe(2);
});
test('browser print protects a deferred snapshot and toolbar print reads full data',async({page})=>{
 const {control}=await setup(page);await page.evaluate(()=>window.dispatchEvent(new Event('beforeprint')));await page.emulateMedia({media:'print'});
 await expect(page.locator('.profile-print-guard')).toBeVisible();await expect(page.locator('.profile-overview')).toBeHidden();expect(control.fullCalls).toBe(0);
 await page.emulateMedia({media:'screen'});await page.evaluate(()=>{window.dispatchEvent(new Event('afterprint'));window.print=()=>{(window as unknown as {printedStage?:string}).printedStage=document.querySelector('.report-surface')?.getAttribute('data-report-stage')||'';};});
 await page.getByRole('button',{name:'打印'}).click();await expect.poll(()=>page.evaluate(()=>(window as unknown as {printedStage?:string}).printedStage)).toBe('full');expect(control.fullCalls).toBe(1);
});
test('opening detail statistics requests full diagnostics once',async({page})=>{
 const {control}=await setup(page);await page.locator('.report-details>summary').click();await expect(page.locator('.report-profile-rebuilt')).toBeVisible();expect(control.fullCalls).toBe(1);
});
test('an obsolete full-read promise cannot block or overwrite a newer chart snapshot',async({page})=>{
 const {control}=await setup(page);let release!:()=>void,seen!:()=>void,delivered!:()=>void;
 const hold=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{seen=resolve;}),returned=new Promise<void>(resolve=>{delivered=resolve;});
 await page.route('**/api/testproject/ext/finEnergy/v1/points/resolve',async route=>{
  if(!(route.request().postDataJSON().ids as string[]).includes('slow-point')){await route.fallback();return;}
  seen();await hold;try{await route.fulfill({json:{ok:true,data:{items:[{id:'slow-point',name:'Old point names',his:true}]}}});}finally{delivered();}
 });
 try{
  control.delayNames=true;await page.getByRole('button',{name:'查看完整诊断',exact:true}).click();await started;
  control.delayNames=false;control.increment=4;await page.getByRole('button',{name:'重置条件',exact:true}).click();
  await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('September daily profile',{exact:true}).click();
  await page.locator('.filter-actions button').filter({has:page.locator('.anticon-search')}).click();await expect.poll(()=>control.chartCalls).toBe(2);await expect(page.locator('.report-profile-first')).toBeVisible();
  await page.getByRole('button',{name:'查看完整诊断',exact:true}).click();await expect.poll(()=>control.fullCalls).toBe(2);await expect(page.locator('.report-profile-rebuilt')).toBeVisible();
  await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('304');
  // The obsolete batch is now abortable; wait for the held server handler,
  // rather than requiring the browser to receive an intentionally aborted reply.
  release();await returned;
  await page.evaluate(()=>new Promise<void>(resolve=>requestAnimationFrame(()=>requestAnimationFrame(()=>resolve()))));
  await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('304');expect(control.fullCalls).toBe(2);
 }finally{release();}
});
