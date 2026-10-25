import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,testRecords} from './fixtures';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';

async function setup(page:Page,mixed=false){
 const request:ReportRequest={kind:'primary',dimension:'metering',nodeIds:['master1','meter1',...(mixed?['gas1']:[])],from:'2026-10-01T00:00:00+08:00',to:'2026-10-03T00:00:00+08:00',period:'day',metric:'coal',perArea:false};
 const records:EnerCubixRecord[]=[...testRecords(),...(mixed?[{id:'gas',kind:'category' as const,name:'天然气',unit:'m³'},{id:'gas1',kind:'meter' as const,name:'燃气表',categoryId:'gas',pointId:'gasPoint',includeInTotals:true}]:[]),{id:'primary-template',kind:'template',name:'两日折算对比',request}];
 const state=await installTransport(page,{records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const current=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:current as unknown as Record<string,unknown>});
  const unit=({coal:'kgce',co2:'kgCO2',rawcoal:'kg',oil:'kg'} as Record<string,string>)[current.metric]+(current.perArea?'/m²':'');
  const series=current.nodeIds.map((id,index)=>({id:id+'|'+(id==='gas1'?'gas':'cat1'),nodeId:id,name:id==='master1'?'测试总表':id==='meter1'?'测试分表':'燃气表',categoryId:id==='gas1'?'gas':'cat1',unit,points:[{ts:current.from,value:10.12345+index,quality:'ok',sourceIds:['point'+index]},{ts:'2026-10-02T00:00:00+08:00',value:mixed&&index===1?null:0,quality:mixed&&index===1?'missingCoefficient':'ok',sourceIds:['point'+index]}]}));
  const result:ReportResult={kind:'primary',from:current.from,to:current.to,period:current.period,series,rows:series.flatMap(s=>s.points.map(p=>({key:s.id+p.ts,nodeId:s.nodeId,name:s.name,categoryId:s.categoryId,...p,unit}))),summary:{totals:series.map(s=>({id:s.id,name:s.name,value:s.points.some(p=>p.value===null)?null:s.points.reduce((sum,p)=>sum+(p.value||0),0),unit,quality:s.points.some(p=>p.value===null)?'missingCoefficient':'ok'}))},warnings:[]};
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'primary');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('两日折算对比',{exact:true}).click();await page.getByRole('button',{name:/查\s*询/}).click();await expect(page.locator('.primary-overview')).toBeVisible();return state;
}
test('primary metrics share grouped charts, readable labels, tables and Excel output',async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));const state=await setup(page);
 for(const [label,unit]of [['标准煤','kgce'],['碳排放','kgCO2'],['原煤','kg'],['石油当量','kg']]){
  await page.locator('label').filter({has:page.getByRole('radio',{name:label,exact:true})}).click();await page.getByRole('button',{name:/查\s*询/}).click();await expect(page.getByRole('heading',{name:`一次能源分析 · ${label}`,exact:true})).toBeVisible();await expect(page.locator('.primary-overview .profile-group')).toHaveCount(1);await expect(page.locator('.primary-overview .profile-group h3')).toHaveText('测试电力 · 折算对比 · '+unit);await expect(page.locator('.primary-overview canvas')).toHaveCount(1);await expect(page.locator('.report-details')).not.toHaveAttribute('open');
 }
 await page.locator('.report-details>summary').click();await expect(page.locator('.report-details')).toContainText('10.12');await expect(page.locator('.report-details')).toContainText('ok');
 await page.getByRole('button',{name:'导出当前报表'}).hover();const event=page.waitForEvent('download');await page.getByRole('menuitem',{name:'Excel 工作簿 (.xlsx)',exact:true}).click();const download=await event;const path=testInfo.outputPath('primary.xlsx');await download.saveAs(path);const zip=await JSZip.loadAsync(await readFile(path));const text=await zip.file('xl/sharedStrings.xml')!.async('string');expect(text).toContain('10.12345');expect(text).toContain('测试总表');expect(state.requests.filter(r=>r.path==='report').at(-1)!.body.metric).toBe('oil');await page.locator('.report-details>summary').click();await page.screenshot({path:testInfo.outputPath('primary-desktop.png'),fullPage:true});expect(errors).toEqual([]);
});
test('primary separates energy categories and preserves missing values on mobile',async({page},testInfo)=>{
 await setup(page,true);await expect(page.locator('.primary-overview .profile-group')).toHaveCount(2);await expect(page.locator('.primary-overview')).toContainText('天然气 · 折算对比 · kgce');await page.setViewportSize({width:390,height:844});await expect(page.locator('.primary-overview canvas')).toHaveCount(2);await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.locator('.report-details>summary').click();await expect(page.locator('.report-details')).toContainText('missingCoefficient');await expect(page.locator('.report-details')).toContainText('—');await page.screenshot({path:testInfo.outputPath('primary-mobile.png'),fullPage:true});
});
