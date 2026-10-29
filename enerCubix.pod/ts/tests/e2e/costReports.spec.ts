import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,openObjects,closeObjects,resultFor} from './fixtures';
import type {ReportRequest,ReportResult} from '../../src/types';

async function selectMeter(page:import('@playwright/test').Page){
 await openObjects(page);
 const checkbox=page.locator('.object-panel .ant-tree-treenode').filter({hasText:'测试分表'}).locator('.ant-tree-checkbox');
 if(!await checkbox.evaluate(element=>element.classList.contains('ant-tree-checkbox-checked')))await checkbox.click();
 await closeObjects(page);
}

function costResult(request:ReportRequest):ReportResult{
 const result=resultFor(request);
 result.series.forEach(series=>{series.unit='元';series.points.forEach((point,index)=>{point.band=index%2?'valley':'sharp';});});
 result.rows.forEach(row=>row.unit='元');
 if(request.kind==='forecast'){
  (result.extra!.forecasts as Record<string,unknown>[]).forEach(row=>{row.unit='元';row.model='meterSum';});
  result.summary.forecastTotals=[{meterIds:['meter1'],value:70,unit:'元',quality:'predicted'}];
  return result;
 }
 result.summary={totals:[{id:'meter1',value:null,quality:'incompleteInterval',unit:'元'}],knownTotals:[{id:'meter1',name:'测试分表',value:12,quality:'filtered',unit:'元'}]};
 result.series[0].points[0]={...result.series[0].points[0],value:null,knownValue:12,knownQuality:'filtered'};
 result.rows=[{nodeId:'meter1',value:null,knownValue:12,quality:'incompleteInterval',knownQuality:'filtered',unit:'元',band:'sharp'}];
 result.extra={usageBasis:'knownUsage',loadBands:[{band:'sharp',value:null,knownValue:12,quality:'incompleteInterval',knownQuality:'filtered',unit:'元'}]};
 if(request.kind==='energyFlow'){
  const node={id:'meter1',nodeId:'meter1',name:'测试分表',nodeType:'meter',categoryId:'cat1',unit:'元',value:null,knownValue:12,knownQuality:'filtered',quality:'incompleteInterval',sourceIds:['point1'],submeter:null,difference:null,balanceQuality:'missing',hasChildren:false,percentage:null,lossEligible:false};
  const graph={graphId:'meter1',objectId:'meter1',basis:'metering',categoryId:'cat1',unit:'元',focusId:'meter1',rootIds:['meter1'],nodes:[node],links:[],unassigned:[],contributionMemberIds:['meter1'],sharedMemberIds:[],additive:true};
  result.extra={...result.extra,energyFlow:graph,energyFlowGraphs:[graph],energyFlowAccounting:{basis:'physicalBoundary',canAdd:true,memberIds:['meter1'],sharedMemberIds:[],sharedMembers:[],unionValue:12,unionQuality:'filtered'}};
 }
 return result;
}

for(const language of ['zh-CN','en-US'])for(const width of [1440,390])test.describe(`${language} cost ${width}`,()=>{
 test.use({locale:language,viewport:{width,height:900}});
 const zh=language==='zh-CN';
 test('queries and exports an available cost subtotal, retaining four-band labels and frozen request',async({page})=>{
  const state=await installTransport(page,{report:costResult});
  await openView(page,'profile');await selectMeter(page);
  await page.locator('label').filter({has:page.getByRole('radio',{name:zh?'费用':'Cost',exact:true})}).click();
  await page.getByRole('button',{name:zh?/查\s*询/:/Query$/}).click();
  await expect(page.locator('.profile-object-summary').first()).toContainText(zh?'已有费用小计':'Available cost subtotal');
  await expect(page.locator('.profile-object-summary').first()).toContainText('12');
  expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.metric).toBe('cost');
  // A draft metric change must not alter the current report's exported snapshot.
  await page.locator('label').filter({has:page.getByRole('radio',{name:zh?'能耗':'Energy',exact:true})}).click();
  await expect(page.getByRole('radio',{name:zh?'能耗':'Energy',exact:true})).toBeChecked();
  await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).click();
  const item=page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true});
  await expect(item).toHaveAttribute('data-menu-id',/^rc-menu-uuid-/);
  const download=page.waitForEvent('download');
  await item.click();
  const file=await (await download).path();const zip=await JSZip.loadAsync(await readFile(file!));
  const text=await zip.file('xl/sharedStrings.xml')!.async('string');
  expect(text).toContain(zh?'尖时':'Sharp peak');
  expect(text).toContain(zh?'已有费用小计':'Available cost subtotal');
  expect(state.requests.filter(r=>r.path==='report')).toHaveLength(1);
  expect(await page.locator('body').evaluate(body=>body.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`../../out/cost-profile-${language}-${width}.png`,fullPage:true});
 });
 test('offers cost queries for flow and forecast and renders sharp-peak coloring',async({page})=>{
  const state=await installTransport(page,{report:costResult});
  for(const view of ['forecast','daily','energyFlow']){
   await openView(page,view);await selectMeter(page);
   await page.locator('label').filter({has:page.getByRole('radio',{name:zh?'费用':'Cost',exact:true})}).click();
   await page.getByRole('button',{name:zh?/查\s*询/:/Query$/}).click();
   await expect(page.getByRole('button',{name:zh?'导出当前报表':'Export current report'})).toBeVisible();
   expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.metric).toBe('cost');
   if(view==='forecast'){
    await expect(page.locator('.report-surface')).toContainText(zh?'不是账单':'are not bills');
    await expect(page.locator('.report-surface')).toContainText(zh?'范围预测费用合计（已去重）':'Predicted cost in scope (deduplicated)');
   }
   if(view==='daily'){
    await page.locator('label').filter({has:page.getByRole('radio',{name:zh?'按尖峰谷平配色':'Color by sharp peak / peak / flat / valley',exact:true})}).click();
    await expect(page.locator('.load-band-legend')).toContainText(zh?'尖时':'Sharp peak');
    expect(await page.locator('body').evaluate(body=>body.scrollWidth<=innerWidth+1)).toBe(true);
   }
   if(view==='energyFlow')await expect(page.locator('.energy-flow-view').first()).toContainText('12');
  }
 });
 test('saves explicit four-band tariff labels without changing the price',async({page})=>{
  const state=await installTransport(page);
  await openView(page,'tariffs');
  await page.getByRole('button',{name:'测试费率',exact:true}).click();
  await page.locator('.ant-select').filter({has:page.getByLabel(zh?'默认时段分类':'Default time-band category',{exact:true})}).click();
  const options=page.locator('.ant-select-dropdown:visible .ant-select-item-option-content');
  for(const band of (zh?['尖时','峰时','平时','谷时']:['Sharp peak','Peak','Standard','Off-peak']))await expect(options.getByText(band,{exact:true})).toBeVisible();
  await options.getByText(zh?'尖时':'Sharp peak',{exact:true}).click();
  await page.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.records.find(row=>row.id==='tariff1')?.band).toBe('sharp');
  expect(state.records.find(row=>row.id==='tariff1')).toMatchObject({rate:1,mode:'flat',rules:[],exceptions:[]});
 });
});
