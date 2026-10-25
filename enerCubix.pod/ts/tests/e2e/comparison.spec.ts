import {test,expect,type Page} from '@playwright/test';
import {installTransport,openView,checkNode,query} from './fixtures';
import {comparisonSlots} from '../../src/comparison';
import type {ReportRequest,ReportResult} from '../../src/types';

async function setup(page:Page){
 await page.clock.setFixedTime(new Date('2026-10-22T14:00:00+08:00'));
 const state=await installTransport(page);
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const request=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:request as unknown as Record<string,unknown>});
  const series=[{id:'meter1|cat1',name:'测试分表',from:request.from,to:request.to,scale:1},...(request.otherFrom?[{id:'meter1|cat1|reference',name:'测试分表 (reference)',from:request.otherFrom,to:request.otherTo!,scale:.8}]:[])].map(line=>({id:line.id,name:line.name,unit:'kWh',categoryId:'cat1',points:comparisonSlots(line.from,line.to,request.period,request.comparisonAlignment).map((ts,i)=>({ts,value:i===2?null:(100+i*7)*line.scale,quality:i===2?'missing':'ok',sourceIds:['point1']}))}));
  const result:ReportResult={kind:'comparison',from:request.from,to:request.to,period:request.period,series,rows:series.flatMap(line=>line.points.map(point=>({...point,name:line.name,unit:line.unit}))),warnings:[],summary:{},extra:{comparisons:[{id:'meter1|cat1',name:'测试分表',categoryId:'cat1',unit:'kWh',current:120,reference:100,difference:20,percentage:20,quality:'ok'}]}};
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'comparison');await checkNode(page);return state;
}
const latest=(state:Awaited<ReturnType<typeof setup>>)=>state.requests.filter(request=>request.path==='report').at(-1)!.body;
test('defaults to matched October/September days and renders grouped bars on desktop and phone',async({page},info)=>{
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));const state=await setup(page);
 await expect(page.locator('.comparison-controls')).toContainText('2026-10-01 — 2026-10-22（22 天）');await expect(page.locator('.comparison-controls')).toContainText('2026-09-01 — 2026-09-22（22 天）');
 await query(page);expect(String(latest(state).from)).toContain('2026-10-01T00:00:00');expect(String(latest(state).to)).toContain('2026-10-23T00:00:00');expect(String(latest(state).otherTo)).toContain('2026-09-23T00:00:00');expect(latest(state).comparisonAlignment).toBe('duration');
 await expect(page.locator('.comparison-overview')).toContainText('本期为深色');await expect(page.locator('.comparison-overview canvas')).toHaveCount(1);await expect(page.locator('.comparison-overview')).toContainText('变化量');
 await page.screenshot({path:info.outputPath('comparison-aligned.png'),fullPage:true});await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:info.outputPath('comparison-mobile.png'),fullPage:true});expect(errors).toEqual([]);
});
test('seven-day shortcut and changing either boundary preserve equal lengths; weekly comparison is paired',async({page})=>{
 const state=await setup(page);await page.getByRole('combobox',{name:'对比时间方式'}).press('ArrowDown');await page.getByText('近 7 天 / 前 7 天',{exact:true}).click();
 await page.getByRole('combobox',{name:'汇总间隔',exact:true}).press('ArrowDown');await page.locator('.ant-select-dropdown:visible').getByText('周',{exact:true}).click();await query(page);
 let request=latest(state);expect(Date.parse(String(request.to))-Date.parse(String(request.from))).toBe(7*86400000);expect(Date.parse(String(request.otherTo))-Date.parse(String(request.otherFrom))).toBe(7*86400000);expect(request.period).toBe('week');
 const start=page.getByRole('textbox',{name:'对比期开始日期',exact:true});await start.fill('2026-08-10');await start.press('Enter');await page.getByRole('heading',{name:'对比分析',exact:true}).click();await query(page);
 request=latest(state);expect(String(request.otherFrom)).toContain('2026-08-10T00:00:00');expect(String(request.otherTo)).toContain('2026-08-17T00:00:00');
 const dates=page.locator('.comparison-controls .ant-picker-range input');await dates.nth(0).fill('2026-10-01');await dates.nth(0).press('Tab');await dates.nth(1).fill('2026-10-03');await dates.nth(1).press('Enter');await page.getByRole('heading',{name:'对比分析',exact:true}).click();await query(page);
 request=latest(state);expect(Date.parse(String(request.to))-Date.parse(String(request.from))).toBe(3*86400000);expect(Date.parse(String(request.otherTo))-Date.parse(String(request.otherFrom))).toBe(3*86400000);
});
test('full months use monthly bars and preserve actual month lengths',async({page})=>{
 const state=await setup(page);await page.getByRole('combobox',{name:'对比时间方式'}).press('ArrowDown');await page.getByText('整月对比',{exact:true}).click();await query(page);
 const request=latest(state);expect(request.comparisonAlignment).toBe('calendarMonth');expect(request.period).toBe('month');expect(Date.parse(String(request.to))-Date.parse(String(request.from))).toBe(31*86400000);expect(Date.parse(String(request.otherTo))-Date.parse(String(request.otherFrom))).toBe(30*86400000);
 await expect(page.locator('.comparison-overview')).toContainText('月份天数不同');await expect(page.locator('.comparison-controls')).toContainText('31 天');await expect(page.locator('.comparison-controls')).toContainText('30 天');
});
test('saving a comparison template retains both ranges and resolves the relative preset next month',async({page})=>{
 const state=await setup(page);await query(page);await page.getByRole('button',{name:/存为模板$/}).click();
 await page.getByLabel('名称',{exact:true}).fill('本月环比模板');await page.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect.poll(()=>state.records.some(record=>record.name==='本月环比模板')).toBe(true);
 const saved=state.records.find(record=>record.name==='本月环比模板')!.request as ReportRequest;expect(saved.comparisonPreset).toBe('monthToDate');expect(saved.comparisonAlignment).toBe('duration');expect(saved.otherFrom).toContain('2026-09-01');expect(saved.otherTo).toContain('2026-09-23');
 await expect(page.getByRole('dialog')).toBeHidden();await page.locator('.template-select .ant-select-selector').click();await page.locator('.ant-select-dropdown:visible .ant-select-item-option-content').getByText('本月环比模板',{exact:true}).click();
 await page.clock.setFixedTime(new Date('2026-11-02T14:00:00+08:00'));await query(page);
 const request=latest(state);expect(String(request.from)).toContain('2026-11-01');expect(String(request.to)).toContain('2026-11-03');expect(String(request.otherFrom)).toContain('2026-10-01');expect(String(request.otherTo)).toContain('2026-10-03');
});
