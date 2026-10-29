import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

async function prepare(page:import('@playwright/test').Page,language:string,water=false){
 const request:ReportRequest={kind:'profile',dimension:'metering',nodeIds:water?['main','branch','water']:['main','branch'],referenceIds:['outside'],from:'2026-09-01T00:00:00+08:00',to:'2026-10-01T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
 const records:EnerCubixRecord[]=[{id:'electric',kind:'category',name:'Electricity',unit:'kWh'},{id:'water-category',kind:'category',name:'Water',unit:'m³'},{id:'main',kind:'totalMeter',name:'Main electricity meter',pointId:'main-point',categoryId:'electric',unit:'kWh'},{id:'branch',kind:'meter',name:'Lighting meter',pointId:'branch-point',categoryId:'electric',unit:'kWh'},{id:'water',kind:'meter',name:'Water meter',pointId:'water-point',categoryId:'water-category',unit:'m³'},{id:'temperature',kind:'binding',name:'Outdoor temperature',pointId:'outside',role:'reference'},{id:'weather',kind:'template',name:'Energy and temperature',request}];
 const state=await installTransport(page,{records,userLocale:language});
 const version=JSON.parse(await readFile(new URL('../../package.json',import.meta.url),'utf8')).version;
 await page.route('**/api/testproject/ext/enerCubix/v1/catalog',route=>route.fulfill({json:{ok:true,data:{version,project:'testproject',user:{name:'Demonstration',canWrite:false},records}}}));
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const current=route.request().postDataJSON() as ReportRequest;
  state.requests.push({path:'report',body:current as unknown as Record<string,unknown>});
  const dates=Array.from({length:30},(_,i)=>`2026-09-${String(i+1).padStart(2,'0')}T00:00:00+08:00`);
  const series=[{id:'main|electric',nodeId:'main',name:'Main electricity meter',categoryId:'electric',unit:'kWh',values:dates.map((_,i)=>100+i)},{id:'branch|electric',nodeId:'branch',name:'Lighting meter',categoryId:'electric',unit:'kWh',values:dates.map((_,i)=>30+i)},...(water?[{id:'water|water-category',nodeId:'water',name:'Water meter',categoryId:'water-category',unit:'m³',values:dates.map((_,i)=>5+i/10)}]:[]),{id:'outside|reference',nodeId:'outside',name:'Outdoor temperature',unit:'°C',values:dates.map((_,i)=>i===10?null:20+Math.round(Math.sin(i/3)*6))}].map(({values,...line})=>({...line,points:values.map((value,i)=>({ts:dates[i],value,quality:value===null?'missing':'ok',sourceIds:[line.nodeId+'-point']}))}));
  const result:ReportResult={kind:'profile',from:current.from,to:current.to,period:'day',series,rows:series.flatMap(line=>line.points.map(point=>({...point,nodeId:line.nodeId,name:line.name,unit:line.unit}))),summary:{totals:[{id:'main|electric',value:3435},{id:'branch|electric',value:1335},...(water?[{id:'water|water-category',value:193.5}]:[])]},warnings:[]};
  await route.fulfill({json:{ok:true,data:result}});
 });
 await page.goto('/#/profile?project=testproject&template=weather');
 await page.getByRole('button',{name:language==='zh-CN'?'查询':'Query',exact:true}).click();
 await expect(page.locator('.profile-group .report-chart canvas')).toHaveCount(water?2:1);
 return state;
}

for(const language of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`reference overlay ${language} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({viewport:mobile?{width:390,height:844}:{width:1440,height:1000}});
 test('keeps the reference curve in the consumption chart and out of meter totals',async({page},info)=>{
  const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
  const state=await prepare(page,language);const zh=language==='zh-CN';
  await expect(page.locator('.profile-group')).toHaveCount(1);
  await expect(page.locator('.profile-object-summary')).toHaveCount(2);
  await expect(page.locator('.profile-group')).toContainText(zh?'参考曲线以折线叠加显示':'Reference lines overlay the consumption chart');
  await expect(page.locator('.profile-object-summary').first().locator('.metric-readout strong')).toContainText('3435');
  expect(state.requests.filter(row=>row.path==='report').at(-1)?.body.referenceIds).toEqual(['outside']);
  await page.getByText(zh?'折线图':'Line chart',{exact:true}).click();
  await expect(page.locator('.profile-group .report-chart canvas')).toHaveCount(1);
  await page.getByText(zh?'柱状图':'Bar chart',{exact:true}).click();
  expect(state.requests.filter(row=>row.path==='report')).toHaveLength(1);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(mobile?390:1440);
  expect(errors).toEqual([]);
  await page.screenshot({path:info.outputPath('reference-overlay.png'),fullPage:true});
 });
});

test('overlays the same reference on separate energy-unit charts and retains it in Excel',async({page})=>{
 await prepare(page,'en-US',true);
 await expect(page.locator('.profile-object-summary')).toHaveCount(3);
 await expect(page.locator('.profile-group').nth(1)).toContainText('m³');
 await page.getByRole('button',{name:'Export current report'}).click();
 const pending=page.waitForEvent('download');await page.getByRole('menuitem',{name:'Excel workbook (.xlsx)'}).click();
 const zip=await JSZip.loadAsync(await readFile((await (await pending).path())!));
 const strings=await zip.file('xl/sharedStrings.xml')!.async('string');
 expect(strings).toContain('Outdoor temperature');expect(strings).toContain('°C');expect(strings).toContain('Main electricity meter');
});
