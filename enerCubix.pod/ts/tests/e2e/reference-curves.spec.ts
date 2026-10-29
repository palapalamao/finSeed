import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openMoreFilters,closeMoreFilters,openObjects,closeObjects} from './fixtures';
import type {EnerCubixRecord,ReportKind,ReportRequest,ReportResult,Series} from '../../src/types';

const kinds:ReportKind[]=['profile','daily','utility','primary','leak','comparison'];
const start='2026-09-01T00:00:00+08:00',end='2026-10-01T00:00:00+08:00';
function request(kind:ReportKind):ReportRequest{return {kind,dimension:'space',spaceSource:'fin',nodeIds:['main'],referenceIds:['outside'],from:start,to:end,period:'day',metric:kind==='primary'?'coal':'energy',perArea:false,...(kind==='comparison'?{otherFrom:'2026-08-01T00:00:00+08:00',otherTo:'2026-09-01T00:00:00+08:00',comparisonAlignment:'calendarMonth',period:'month'}:{})};}
function report(q:ReportRequest):ReportResult{
 const daily=q.kind==='daily',comparison=q.kind==='comparison';
 const times=Array.from({length:daily?24:comparison?1:30},(_,i)=>daily?`2026-09-01T${String(i).padStart(2,'0')}:00:00+08:00`:`2026-09-${String(i+1).padStart(2,'0')}T00:00:00+08:00`);
 const points=times.map((ts,i)=>({ts,value:100+i,quality:'ok',sourceIds:['main-point']}));
 const series:Series[]=[{id:'main|e',nodeId:'main',categoryId:'e',name:'Main electricity meter',unit:q.kind==='primary'?'kgce':'kWh',points}];
 if(comparison)series.push({...series[0],id:'main|e|reference',points:points.map(point=>({...point,ts:point.ts.replace('09-','08-'),value:90}))});
 if(q.referenceIds?.includes('outside')){
  const reference:Series={id:'outside|reference',nodeId:'weather',name:'Outdoor temperature',unit:'°C',role:'reference',referencePeriod:'current',points:times.map((ts,i)=>({ts,value:i===5?null:i===0?0:19+Math.sin(i/3)*6,quality:i===5?'missing':'partial',sourceIds:['outside'],validSamples:i===5?0:20,expectedSamples:30,missingSamples:i===5?30:10,naSamples:0}))};series.push(reference);
  if(comparison)series.push({...reference,id:'outside|reference|comparison',referencePeriod:'comparison',points:reference.points.map(point=>({...point,ts:point.ts.replace('09-','08-'),value:25}))});
 }
 return {kind:q.kind,from:q.from,to:q.to,period:q.period,series,rows:[...points.map(point=>({...point,nodeId:'main',categoryId:'e',name:'Main electricity meter',unit:series[0].unit,total:point.value,submeter:point.value-10})),...series.filter(line=>line.role==='reference').flatMap(line=>line.points.map(point=>({...point,nodeId:line.nodeId,name:line.name,unit:line.unit,role:line.role,referencePeriod:line.referencePeriod})))],summary:{totals:[{id:'main|e',value:3435,unit:series[0].unit}]},warnings:[],extra:{...(q.kind==='leak'?{leakTotals:[{nodeId:'main',categoryId:'e',unit:'kWh',total:3435,submeter:3135,difference:300,percentage:8.73}],leakBranches:points.map(point=>({nodeId:'main',categoryId:'e',unit:'kWh',ts:point.ts,branchId:'child',name:'Lighting meter',value:point.value!-10}))}:{}),...(comparison?{comparisons:[{id:'main|e',name:'Main electricity meter',unit:'kWh',current:3435,reference:3000,difference:435,percentage:14.5}]}:{}),...(q.kind==='utility'?{utilityShares:[],utilityMembers:[]}:{}),...(daily?{loadBands:[]}:{} )}};
}

for(const language of ['zh-CN','en-US'])for(const mobile of [false,true])test(`reference curves across reports and trees ${language} ${mobile?'mobile':'desktop'}`,async({page},info)=>{
 test.setTimeout(120000);
 await page.setViewportSize(mobile?{width:390,height:844}:{width:1440,height:1000});
 const zh=language==='zh-CN',errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 const records:EnerCubixRecord[]=[{id:'site',kind:'space',name:'Campus',nativeReadonly:true},{id:'e',kind:'category',name:'Electricity',unit:'kWh'},{id:'company',kind:'organization',name:'Company'}, {id:'main',kind:'totalMeter',name:'Main electricity meter',pointId:'main-point',nativeEquip:true,nativeSpaceId:'site',categoryId:'e',spaceId:'site',organizationId:'company'},{id:'child',kind:'meter',name:'Lighting meter',meterParentId:'main',pointId:'child-point',categoryId:'e'},{id:'weather',kind:'binding',name:'Outdoor temperature',pointId:'outside',role:'reference'},...kinds.map(kind=>({id:`ref-${kind}`,kind:'template' as const,name:`Reference ${kind}`,request:request(kind)}))];
 const state=await installTransport(page,{records,userLocale:language,spaceSource:'fin',report});
 for(const kind of kinds){
  await page.goto(`/#/${kind}?project=testproject&template=ref-${kind}`);
  await openMoreFilters(page);await expect(page.getByText(zh?'参考曲线（可选，使用 FIN 原始历史）':'Reference curves (optional, using original FIN history)',{exact:true})).toBeVisible();
  await expect(page.locator('.advanced-query-fields').getByText('Outdoor temperature',{exact:true})).toBeVisible();await closeMoreFilters(page);
  await page.getByRole('button',{name:zh?'查询':'Query',exact:true}).click();await expect(page.locator('.report-chart canvas')).toHaveCount(1);
  expect(state.requests.filter(row=>row.path==='report').at(-1)?.body.referenceIds).toEqual(['outside']);
  await expect(page.locator('.report-surface')).toContainText(kind==='daily'?(zh?'按查询期间各小时':'Average available observations'):(zh?'参考曲线叠加在原图':'Reference lines overlay the original chart'));
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(mobile?390:1440);
  if(kind==='daily'||kind==='comparison')await page.screenshot({path:info.outputPath(`${kind}.png`),fullPage:true});
 }
 // Reference selections survive switching the analysis tree. The object itself
 // must be selected again because each tree has its own scope.
 await page.goto('/#/daily?project=testproject&template=ref-daily');
 await page.getByRole('button',{name:zh?'退出模板':'Exit template',exact:true}).click();
 await openMoreFilters(page);await page.locator('.filter-field').filter({hasText:zh?'参考曲线（可选':'Reference curves (optional'}).getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('Outdoor temperature',{exact:true}).click();await closeMoreFilters(page);
 for(const dimension of [zh?'计量':'Metering',zh?'组织':'Organization',zh?'空间':'Space']){
  await page.locator('label').filter({has:page.getByRole('radio',{name:dimension,exact:true})}).click();
  await openMoreFilters(page);await expect(page.locator('.advanced-query-fields').getByText('Outdoor temperature',{exact:true})).toBeVisible();await closeMoreFilters(page);
  await openObjects(page);const meter=page.locator('.object-panel .ant-tree-treenode').filter({hasText:'Main electricity meter'});if(!await meter.isVisible()){const expand=page.locator('.object-panel .ant-tree-switcher_close').first();await expand.click();}await meter.locator('.ant-tree-checkbox').click();await closeObjects(page);
  await page.getByRole('button',{name:zh?'查询':'Query',exact:true}).click();await expect(page.locator('.report-chart canvas')).toHaveCount(1);
  expect(state.requests.filter(row=>row.path==='report').at(-1)?.body.referenceIds).toEqual(['outside']);
 }
 await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).click();const download=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)'}).click();
 const zip=await JSZip.loadAsync(await readFile((await (await download).path())!));const strings=await zip.file('xl/sharedStrings.xml')!.async('string');expect(strings).toContain('Outdoor temperature');expect(strings).toContain('°C');expect(strings).toContain(zh?'有效小时数':'Valid hours');expect(errors).toEqual([]);
});
