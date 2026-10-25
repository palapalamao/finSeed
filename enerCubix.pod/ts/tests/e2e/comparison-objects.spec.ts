import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,checkNode,query,openObjects,closeObjects} from './fixtures';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';

async function setup(page:Page,legacy=false){
 const records:EnerCubixRecord[]=[{id:'s',kind:'space',name:'测试楼层'},{id:'c',kind:'category',name:'电能',unit:'kWh'},...['一号电表','二号电表','三号电表'].map((name,i)=>({id:'m'+i,kind:'meter' as const,name,pointId:'point'+(i+1),spaceId:'s',categoryId:'c',unit:'kWh'}))];
 if(legacy)records.push({id:'old',kind:'template',name:'旧对象对比',request:{kind:'comparison',dimension:'space',nodeIds:['m0'],referenceIds:['m1'],from:'2026-10-01T00:00:00+08:00',to:'2026-10-08T00:00:00+08:00',period:'day',metric:'energy',perArea:false}});
 const state=await installTransport(page,{records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const request=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:request as unknown as Record<string,unknown>});
  const amounts:Record<string,number>={m0:120,m1:60,m2:30};const baseline=request.baselineId||request.nodeIds[0];const targets=request.nodeIds.filter(id=>id!==baseline);
  const series=request.nodeIds.map(id=>({id:id+'|c',nodeId:id,name:records.find(r=>r.id===id)!.name,categoryId:'c',unit:'kWh',points:[{ts:request.from,value:amounts[id],quality:'ok',sourceIds:['point1']}]}));
  const result:ReportResult={kind:'comparison',from:request.from,to:request.to,period:request.period,series,rows:series.map(line=>({name:line.name,value:amounts[line.nodeId],unit:'kWh'})),warnings:[],summary:{totals:series.map(line=>({id:line.id,name:line.name,value:amounts[line.nodeId],unit:'kWh'}))},extra:{comparisonBaselineId:baseline,comparisonBaselineName:records.find(r=>r.id===baseline)?.name,comparisons:targets.map(id=>({id:id+'|c',name:records.find(r=>r.id===id)!.name,referenceId:baseline,referenceName:records.find(r=>r.id===baseline)!.name,current:amounts[id],reference:amounts[baseline],difference:amounts[id]-amounts[baseline],percentage:(amounts[id]-amounts[baseline])/amounts[baseline]*100,unit:'kWh'}))}};
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'comparison');
 if(!legacy){await page.locator('label').filter({has:page.getByRole('radio',{name:'不同对象（同一时段）',exact:true})}).click();await checkNode(page,'一号电表');await checkNode(page,'二号电表');}
 return state;
}
async function baseline(page:Page,name:string){await page.getByRole('combobox',{name:'基准对象',exact:true}).press('ArrowDown');await page.locator('.ant-select-dropdown:visible .ant-select-item-option-content').getByText(name,{exact:true}).click();}
const latest=(state:Awaited<ReturnType<typeof setup>>)=>state.requests.filter(row=>row.path==='report').at(-1)!.body;

test('one object tree and an explicit baseline drive the result and readable comparison columns',async({page},info)=>{
 const state=await setup(page);await expect(page.getByPlaceholder('选择对比对象',{exact:true})).toHaveCount(0);await openObjects(page);await expect(page.locator('.object-tree-title')).toContainText('对比对象');await closeObjects(page);
 await baseline(page,'二号电表');await query(page);expect(latest(state).nodeIds).toEqual(['m0','m1']);expect(latest(state).referenceIds).toBeUndefined();expect(latest(state).baselineId).toBe('m1');
 await expect(page.locator('.comparison-baseline strong')).toHaveText('二号电表');await expect(page.locator('.profile-object-summary .metric-readout strong')).toHaveText(['120 kWh','60 kWh','60 kWh','100 %']);
 await baseline(page,'一号电表');await query(page);await expect(page.locator('.comparison-baseline strong')).toHaveText('一号电表');await expect(page.locator('.profile-object-summary .metric-readout strong')).toHaveText(['60 kWh','120 kWh','-60 kWh','-50 %']);
 await page.locator('.report-details summary').click();await expect(page.getByRole('columnheader',{name:'基准用量',exact:true})).toBeVisible();
 await page.screenshot({path:info.outputPath('object-baseline.png'),fullPage:true});await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test('removing the baseline requires a new explicit choice',async({page})=>{
 const state=await setup(page);await checkNode(page,'三号电表');await baseline(page,'二号电表');await checkNode(page,'二号电表');
 await page.getByRole('button',{name:/查\s*询/}).click();await expect(page.getByText('请从已选对象中指定基准对象',{exact:true})).toBeVisible();expect(state.requests.filter(row=>row.path==='report')).toHaveLength(0);
});
test('template save and reload retain the explicit baseline without a second object selector',async({page})=>{
 const state=await setup(page);await baseline(page,'二号电表');await page.getByRole('button',{name:/存为模板$/}).click();await page.getByLabel('名称',{exact:true}).fill('指定基准对比');await page.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect.poll(()=>state.records.some(row=>row.name==='指定基准对比')).toBe(true);const saved=state.records.find(row=>row.name==='指定基准对比')!.request as ReportRequest;expect(saved.baselineId).toBe('m1');expect(saved.referenceIds).toBeUndefined();
 await expect(page.getByRole('dialog')).toBeHidden();await page.locator('.template-select .ant-select-selector').click();await page.locator('.ant-select-dropdown:visible .ant-select-item-option-content').getByText('指定基准对比',{exact:true}).click();await query(page);expect(latest(state).baselineId).toBe('m1');await expect(page.locator('.comparison-baseline strong')).toHaveText('二号电表');
});
test('legacy extra object references join the same tree selection',async({page})=>{
 const state=await setup(page,true);await page.locator('.template-select .ant-select-selector').click();await page.locator('.ant-select-dropdown:visible .ant-select-item-option-content').getByText('旧对象对比',{exact:true}).click();await query(page);
 expect(latest(state).nodeIds).toEqual(['m0','m1']);expect(latest(state).baselineId).toBe('m0');expect(latest(state).referenceIds).toBeUndefined();await openObjects(page);await expect(page.locator('.locked-paths')).toContainText('二号电表');
});
test('Excel export retains the displayed baseline and comparison meaning',async({page},info)=>{
 await setup(page);await baseline(page,'二号电表');await query(page);
 await page.getByRole('button',{name:'导出当前报表'}).hover();await page.getByRole('menuitem',{name:'Excel 工作簿 (.xlsx)',exact:true}).waitFor();const event=page.waitForEvent('download');await page.getByRole('menuitem',{name:'Excel 工作簿 (.xlsx)',exact:true}).click();
 const download=await event,path=info.outputPath('baseline-comparison.xlsx');await download.saveAs(path);const zip=await JSZip.loadAsync(await readFile(path));const text=await zip.file('xl/sharedStrings.xml')!.async('string');
 expect(text).toContain('二号电表');expect(text).toContain('基准对象');expect(text).toContain('基准用量');expect(text).toContain('对象用量');expect(text).toContain('相对基准变化率');expect(text).not.toContain('baselineId');
});
