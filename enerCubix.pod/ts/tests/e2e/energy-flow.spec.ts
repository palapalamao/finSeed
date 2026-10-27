import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {PNG} from 'pngjs';
import type {ReportRequest,EnerCubixRecord} from '../../src/types';
import {setupEnergyFlow,selectEnergyFlowScope,summaryId,differenceId} from './energy-flow-fixture';

const graph=(page:Page)=>page.locator('.energy-flow-graph');
const flowNode=(page:Page,id:string)=>graph(page).locator(`[data-flow-node="${id}"]`);
const flowEdge=(page:Page,source:string,target?:string)=>graph(page).locator(`[data-flow-source="${source}"]${target?`[data-flow-target="${target}"]`:''}`);
const metric=(page:Page,label:string)=>page.locator('.energy-flow-metric').filter({has:page.getByText(label,{exact:true})}).locator('strong');
const reportRequests=(state:Awaited<ReturnType<typeof setupEnergyFlow>>)=>state.requests.filter(row=>row.path==='report');
test('exports the selected SVG flow as a real PNG and a paginated PDF',async({page},testInfo)=>{
 await setupEnergyFlow(page);
 await expect(flowNode(page,'a')).toBeVisible();
 await graph(page).getByRole('button',{name:/^东楼总表：/}).click();
 for(const [label,extension]of [['图表与摘要图片 (.png)','png'],['PDF 报表（完整明细，分页）(.pdf)','pdf']]){
  await page.getByRole('button',{name:/导出当前报表/}).hover();
  const pending=page.waitForEvent('download');
  await page.getByRole('menuitem',{name:label,exact:true}).click();
  const download=await pending;
  await expect(page.getByText('导出完成，数据与当前报表一致',{exact:true})).toBeVisible();
  const file=testInfo.outputPath('energy-flow-current.'+extension);
  await download.saveAs(file);const bytes=await readFile(file);
  expect(bytes.length).toBeGreaterThan(15000);
  if(extension==='png'){
   const image=PNG.sync.read(bytes);expect(image.width).toBeGreaterThan(900);expect(image.height).toBeGreaterThan(400);
   let colored=0,pale=0;for(let offset=0;offset<image.data.length;offset+=4){
    const [red,green,blue,alpha]=image.data.subarray(offset,offset+4);
    if(red<180&&green>red+10&&alpha>0)colored++;
    if(red>180&&red<245&&green>red+8&&blue>red+4&&alpha>0)pale++;
   }
   expect(colored).toBeGreaterThan(1000);
   expect(pale).toBeGreaterThan(colored*2);
  }else{expect(bytes.subarray(0,5).toString()).toBe('%PDF-');expect((bytes.toString('latin1').match(/\/Type\s*\/Page\b/g)||[]).length).toBeGreaterThanOrEqual(1);}
  await expect(page.getByText('导出完成，数据与当前报表一致',{exact:true})).toHaveCount(0);
 }
 await expect(metric(page,'当前表计用量')).toHaveText('1,000kWh');
});
async function chooseEnergy(page:Page,label:string,english=false){
 await page.getByRole('combobox',{name:english?'Energy type':'能源类型',exact:true}).press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText(label,{exact:true}).click();
 await page.locator('.filter-actions button').first().click();
}

test('requires scope selection and a manual query before counting independent mains once',async({page},testInfo)=>{
 await page.clock.setFixedTime(new Date('2026-10-23T04:00:00Z'));
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 const state=await setupEnergyFlow(page,{query:false});
 await expect(page.locator('.object-select-button')).toBeVisible();
 await expect(page.locator('.filter-actions button').first()).toBeDisabled();
 expect(reportRequests(state)).toHaveLength(0);
 await selectEnergyFlowScope(page);
 await expect(flowNode(page,summaryId)).toHaveAttribute('data-flow-value','1800');
 expect(reportRequests(state)).toHaveLength(1);
 const request=reportRequests(state)[0].body;
 expect(request).toMatchObject({kind:'energyFlow',dimension:'space',categoryId:'electric',nodeIds:['flow-scope'],period:'day',metric:'energy',perArea:false,from:'2026-10-01T00:00:00+08:00',to:'2026-10-23T12:00:00+08:00'});
 expect(Object.keys(request).sort()).toEqual(['kind','dimension','categoryId','nodeIds','from','to','period','metric','perArea'].sort());
 await expect(page.getByRole('tab',{name:'构成与排名',exact:true})).toHaveAttribute('aria-selected','true');
 await expect(page.getByRole('tab',{name:'能流图',exact:true})).toHaveAttribute('aria-selected','true');
 await expect(page.getByRole('button',{name:/^选择对象/})).toBeVisible();
 await expect(page.getByRole('combobox',{name:'能源类型',exact:true})).toBeVisible();
 await expect(page.locator('.category-filter .ant-select')).not.toHaveClass(/ant-select-multiple/);
 await expect(metric(page,'总表统计合计')).toHaveText('1,800kWh');
 await expect(metric(page,'直属分表合计')).toHaveText('1,400kWh');
 await expect(metric(page,'计量差额')).toHaveText('400kWh');
 await expect(metric(page,'总表数量')).toHaveText('2');
 await expect(graph(page).locator('.energy-flow-column-title')).toHaveText(['能源汇总','总表','直属分表']);
 await expect(flowEdge(page,summaryId,'a')).toHaveAttribute('data-flow-value','1000');
 await expect(flowEdge(page,'a',differenceId('a'))).toHaveAttribute('data-flow-value','200');
 await expect(page.locator('.energy-flow-unassigned')).toContainText('未挂接电表');
 await expect(page.locator('.energy-flow-unassigned')).toContainText('91');
 await expect(flowNode(page,'orphan')).toHaveCount(0);
 await expect(page.locator('.energy-flow-details').first()).toContainText('测试源点一');
 await page.screenshot({path:testInfo.outputPath('energy-flow-desktop-zh.png'),fullPage:true});
 expect(errors).toEqual([]);
});

test('drills three levels locally and returns through the path and overview',async({page})=>{
 const state=await setupEnergyFlow(page);
 await expect(flowNode(page,'a')).toBeVisible();
 await expect(flowNode(page,'a11')).toHaveCount(0);
 await graph(page).getByRole('button',{name:/^东楼总表：/}).click();
 await expect(metric(page,'当前表计用量')).toHaveText('1,000kWh');
 await expect(flowNode(page,'a11')).toHaveAttribute('data-flow-value','400');
 await expect(flowNode(page,'b')).toHaveCount(0);
 await expect(graph(page).locator('.energy-flow-column-title')).toHaveText(['当前表计','下级分表','下一级去向']);
 await graph(page).getByRole('button',{name:/^东楼空调分表：/}).press('Enter');
 await expect(metric(page,'当前表计用量')).toHaveText('600kWh');
 await expect(page.getByRole('navigation',{name:'能流路径'})).toContainText('全项目概览/东楼总表/东楼空调分表');
 await expect(page.locator('.energy-flow-details').first().locator('[data-flow-row]')).toHaveCount(4);
 await page.getByRole('navigation',{name:'能流路径'}).getByRole('button',{name:'东楼总表',exact:true}).click();
 await expect(metric(page,'当前表计用量')).toHaveText('1,000kWh');
 await page.getByRole('button',{name:'返回概览',exact:true}).click();
 await expect(metric(page,'总表统计合计')).toHaveText('1,800kWh');
 await expect(flowNode(page,'b')).toBeVisible();
 await expect(page.getByRole('button',{name:'返回概览',exact:true})).toBeDisabled();
 expect(reportRequests(state)).toHaveLength(1);
});

test('switches exactly one energy and queries the currently selected relative dates',async({page})=>{
 await page.clock.setFixedTime(new Date('2026-10-23T04:00:00Z'));
 const state=await setupEnergyFlow(page);
 await expect(flowNode(page,summaryId)).toBeVisible();
 await chooseEnergy(page,'测试水量');
 await expect(flowNode(page,'__energyFlow__:water')).toHaveAttribute('data-flow-value','120');
 expect(reportRequests(state).at(-1)?.body).toMatchObject({categoryId:'water',nodeIds:['flow-scope'],metric:'energy',period:'day',perArea:false});
 await expect(page.locator('.category-filter .ant-select-selection-item')).toHaveText('测试水量');
 await page.locator('.filter-field').filter({has:page.getByText('相对时间',{exact:true})}).getByRole('combobox').press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText('上月',{exact:true}).click();
 const response=page.waitForResponse(response=>response.url().endsWith('/v1/report')&&response.request().postDataJSON().from==='2026-09-01T00:00:00+08:00');
 await page.getByRole('button',{name:'查询',exact:true}).click();await response;
 await expect(flowNode(page,'water-main')).toBeVisible();
 expect(reportRequests(state).at(-1)?.body).toMatchObject({categoryId:'water',from:'2026-09-01T00:00:00+08:00',to:'2026-10-01T00:00:00+08:00',nodeIds:['flow-scope']});
 await expect(metric(page,'总表统计合计')).toHaveText('120m³');
});

test('keeps real missing and negative-balance readings while hiding only their outgoing flows',async({page})=>{
 const state=await setupEnergyFlow(page,{abnormal:true});
 await expect(flowNode(page,summaryId)).toHaveAttribute('data-flow-value','1500');
 await expect(flowNode(page,'b')).toHaveAttribute('data-flow-value','500');
 await expect(flowNode(page,'b1')).toHaveAttribute('data-flow-value','600');
 await expect(flowEdge(page,'b')).toHaveCount(0);
 await expect(flowEdge(page,'a','a1')).toHaveAttribute('data-flow-value','600');
 await expect(page.locator('.energy-flow-notices')).toContainText('差额为 -100 kWh');
 await expect(page.locator('[data-flow-row="b"]')).toContainText('分表大于总表');
 await graph(page).getByRole('button',{name:/^东楼总表：/}).click();
 await expect(flowNode(page,'a1')).toHaveAttribute('data-flow-value','600');
 await expect(flowNode(page,'a11')).not.toHaveAttribute('data-flow-value');
 await expect(flowNode(page,'a11')).toContainText('—');
 await expect(page.locator('[data-flow-row="a11"]')).toContainText('缺测');
 await expect(flowEdge(page,'a1')).toHaveCount(0);
 await expect(flowEdge(page,'a','a1')).toHaveAttribute('data-flow-value','600');
 await expect(flowEdge(page,'a',differenceId('a'))).toHaveAttribute('data-flow-value','200');
 await expect(page.locator('.energy-flow-notices')).toContainText('东楼空调分表：缺测或计量关系不完整');
 expect(reportRequests(state)).toHaveLength(1);
});

test('saves and manually queries a template with its selected scope and single energy',async({page})=>{
 const state=await setupEnergyFlow(page);
 await expect(flowNode(page,summaryId)).toBeVisible();
 await chooseEnergy(page,'测试水量');
 await expect(flowNode(page,'water-main')).toBeVisible();
 await page.getByRole('button',{name:'存为模板',exact:true}).click();
 const editor=page.getByRole('dialog').filter({hasText:'新增报表模板'});
 await editor.getByRole('textbox',{name:/名称/}).fill('项目水能流模板');
 await expect(editor.getByLabel('固定分析对象',{exact:true})).toBeHidden();
 await editor.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect(editor).toBeHidden();
 const saved=state.records.find(record=>record.kind==='template'&&record.name==='项目水能流模板') as EnerCubixRecord;
 expect(saved).toBeDefined();
 expect(saved.request as ReportRequest).toMatchObject({kind:'energyFlow',dimension:'space',categoryId:'water',nodeIds:['flow-scope'],period:'day',metric:'energy',perArea:false});
 await page.getByRole('button',{name:'重置条件',exact:true}).click();
 await page.getByRole('combobox',{name:'报表模板',exact:true}).press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText('项目水能流模板',{exact:true}).click();
 await expect(page.getByRole('combobox',{name:'能源类型',exact:true})).toBeDisabled();
 await page.getByRole('button',{name:'查询',exact:true}).click();
 await expect(flowNode(page,'__energyFlow__:water')).toHaveAttribute('data-flow-value','120');
 expect(reportRequests(state).at(-1)?.body).toMatchObject({categoryId:'water',nodeIds:['flow-scope']});
 await expect(page.getByText('请先选择分析对象',{exact:true})).toHaveCount(0);
});

test('saves a drilled subtree and restores the project overview from the applied template',async({page})=>{
 const state=await setupEnergyFlow(page);
 await expect(flowNode(page,'a')).toBeVisible();
 await graph(page).getByRole('button',{name:/^东楼总表：/}).click();
 await page.getByRole('button',{name:'存为模板',exact:true}).click();
 const editor=page.getByRole('dialog').filter({hasText:'新增报表模板'});
 await editor.getByRole('textbox',{name:/名称/}).fill('东楼子树模板');
 await editor.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect(editor).toBeHidden();
 const saved=state.records.find(record=>record.kind==='template'&&record.name==='东楼子树模板') as EnerCubixRecord;
 expect(saved.request as ReportRequest).toMatchObject({categoryId:'electric',nodeIds:['a']});
 await page.getByRole('button',{name:'重置条件',exact:true}).click();
 await page.getByRole('combobox',{name:'报表模板',exact:true}).press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText('东楼子树模板',{exact:true}).click();
 await page.getByRole('button',{name:'查询',exact:true}).click();
 await expect(metric(page,'当前表计用量')).toHaveText('1,000kWh');
 await expect(flowNode(page,summaryId)).toHaveCount(0);
 expect(reportRequests(state).at(-1)?.body).toMatchObject({nodeIds:['a']});
 await page.getByRole('button',{name:'返回概览',exact:true}).click();
 await page.locator('.object-panel .ant-tree-treenode').filter({hasText:'测试范围'}).first().locator('.ant-tree-checkbox').click();
 await page.locator('.object-selector-drawer .ant-drawer-footer button').click();
 await page.locator('.filter-actions button').first().click();
 await expect(metric(page,'总表统计合计')).toHaveText('1,800kWh');
 expect(reportRequests(state).at(-1)?.body).toMatchObject({nodeIds:['flow-scope']});
 await expect(page.getByRole('combobox',{name:'能源类型',exact:true})).toBeEnabled();
});

test('retains an explicit date range when saving and applying an energy-flow template',async({page})=>{
 await page.clock.setFixedTime(new Date('2026-10-23T04:00:00Z'));
 const state=await setupEnergyFlow(page);
 await expect(flowNode(page,summaryId)).toBeVisible();
 const dates=page.locator('.filter-period .ant-picker-range input');
 await dates.nth(0).fill('2026-09-05 00:00');await dates.nth(0).press('Tab');
 await dates.nth(1).fill('2026-09-08 00:00');await dates.nth(1).press('Enter');
 await page.getByRole('heading',{name:'能流图',exact:true}).click();
 await page.getByRole('button',{name:'查询',exact:true}).click();
 await expect.poll(()=>reportRequests(state).at(-1)?.body.from).toBe('2026-09-05T00:00:00+08:00');
 await page.getByRole('button',{name:'存为模板',exact:true}).click();
 const editor=page.getByRole('dialog').filter({hasText:'新增报表模板'});
 await editor.getByRole('textbox',{name:/名称/}).fill('固定区间模板');
 await editor.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect(editor).toBeHidden();
 const saved=state.records.find(record=>record.kind==='template'&&record.name==='固定区间模板') as EnerCubixRecord;
 expect(saved.preset).toBeUndefined();
 await page.getByRole('button',{name:'重置条件',exact:true}).click();
 await page.getByRole('combobox',{name:'报表模板',exact:true}).press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText('固定区间模板',{exact:true}).click();
 await page.getByRole('button',{name:'查询',exact:true}).click();
 await expect.poll(()=>reportRequests(state).at(-1)?.body).toMatchObject({from:'2026-09-05T00:00:00+08:00',to:'2026-09-08T00:00:00+08:00'});
});

test.describe('English energy flow',()=>{
 test.use({locale:'en-US'});
 test('localizes controls and scoped XLSX rows and series while retaining Chinese business names',async({page},testInfo)=>{
  const state=await setupEnergyFlow(page);
  await expect(page.getByRole('heading',{name:'Energy flow',exact:true})).toBeVisible();
  await expect(page.getByRole('combobox',{name:'Energy type',exact:true})).toBeVisible();
  await expect(flowNode(page,summaryId)).toHaveAccessibleName('Utility summary: 1,800 kWh');
  await expect(flowNode(page,'b')).toHaveAccessibleName('能源汇总: 800 kWh');
  await expect(metric(page,'Main meter total')).toHaveText('1,800kWh');
  await expect(page.getByRole('columnheader',{name:'Metering object',exact:true}).first()).toBeVisible();
  await graph(page).getByRole('button',{name:/^东楼总表:/}).click();
  await graph(page).getByRole('button',{name:/^东楼空调分表:/}).click();
  await expect(page.getByRole('navigation',{name:'Energy flow path'})).toContainText('Project overview/东楼总表/东楼空调分表');
  await expect(page.getByRole('button',{name:'Back to overview',exact:true})).toBeEnabled();
  await page.getByRole('button',{name:/Export current report/}).hover();
  const downloadEvent=page.waitForEvent('download');
  await page.getByRole('menuitem',{name:'Excel workbook (.xlsx)',exact:true}).click();
  const download=await downloadEvent;const path=testInfo.outputPath('energy-flow-subtree-en.xlsx');await download.saveAs(path);
  expect(download.suggestedFilename()).toContain('Energy flow');
  const zip=await JSZip.loadAsync(await readFile(path));
  const strings=await zip.file('xl/sharedStrings.xml')!.async('string');
  const workbook=await zip.file('xl/workbook.xml')!.async('string');
  const details=await zip.file('xl/worksheets/sheet2.xml')!.async('string');
  const series=await zip.file('xl/worksheets/sheet3.xml')!.async('string');
  expect(workbook).toContain('Statistics');expect(workbook).toContain('Time series and quality');
  for(const header of ['Metering object','Data quality','Source points','Node type'])expect(strings).toContain(header);
  for(const name of ['东楼空调分表','机房冷机','机房水泵','Metering difference'])expect(strings).toContain(name);
  for(const name of ['西楼照明分表','能源汇总','未挂接电表','东楼照明分表'])expect(strings).not.toContain(name);
  expect(strings).not.toContain('统计明细');expect(strings).not.toContain('计量差额');
  expect((details.match(/<row\b/g)||[])).toHaveLength(5);
  expect((series.match(/<row\b/g)||[])).toHaveLength(5);
  expect(reportRequests(state)).toHaveLength(1);
  await page.screenshot({path:testInfo.outputPath('energy-flow-desktop-en.png'),fullPage:true});
 });
});

for(const language of ['zh-CN','en-US'])test.describe(`mobile ${language}`,()=>{
 test.use({locale:language,viewport:{width:390,height:844},hasTouch:true});
 test('keeps the page within 390 px while the graph scrolls and table drill remains usable',async({page},testInfo)=>{
  const english=language==='en-US';const state=await setupEnergyFlow(page);
  await expect(flowNode(page,summaryId)).toBeVisible();
  await expect(page.getByRole('button',{name:english?'Open navigation':'打开导航',exact:true})).toBeVisible();
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  const canvas=page.getByLabel(english?'Energy flow canvas; scroll horizontally':'能流图画布，可横向滚动',{exact:true});
  await expect(canvas).toHaveCSS('overflow-x','auto');
  expect(await canvas.evaluate(element=>element.scrollWidth>element.clientWidth)).toBe(true);
  await canvas.hover();await page.mouse.wheel(500,0);
  await expect.poll(()=>canvas.evaluate(element=>element.scrollLeft)).toBeGreaterThan(0);
  await page.mouse.move(0,0);await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({path:testInfo.outputPath(`energy-flow-mobile-${language}.png`),fullPage:true});
  await page.locator('.energy-flow-details').first().getByRole('button',{name:/^东楼总表/}).tap();
  await expect(metric(page,english?'Selected meter consumption':'当前表计用量')).toHaveText('1,000kWh');
  await expect(page.locator('.energy-flow-unassigned')).toHaveCount(0);
  await page.getByRole('button',{name:english?'Back to overview':'返回概览',exact:true}).tap();
  await expect(metric(page,english?'Main meter total':'总表统计合计')).toHaveText('1,800kWh');
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  expect(reportRequests(state)).toHaveLength(1);
 });
});
