import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView} from './fixtures';
import type {EnergyFlowData,EnergyFlowNode} from '../../src/energyFlow';
import type {ReportResult} from '../../src/types';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`historic flow ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('selects a saved topology segment and exports only its own readings',async({page},testInfo)=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
  const state=await installTransport(page,{records:[{id:'electric',kind:'category',name:'电能',unit:'kWh'},{id:'total',kind:'totalMeter',name:'总电表',pointId:'pt',categoryId:'electric',unit:'kWh',includeInTotals:true},{id:'a',kind:'meter',name:'分电表A',pointId:'pa',meterParentId:'total',categoryId:'electric',unit:'kWh',includeInTotals:true},{id:'b',kind:'meter',name:'分电表B',pointId:'pb',meterParentId:'total',categoryId:'electric',unit:'kWh',includeInTotals:true}]});
  const start='2026-10-25T00:00:00+08:00',change='2026-10-25T01:00:00+08:00',end='2026-10-25T02:00:00+08:00';
  const node=(id:string,name:string,value:number,parentId?:string):EnergyFlowNode=>({id,name,value,parentId,nodeType:'meter',categoryId:'electric',unit:'kWh',quality:'ok',sourceIds:[`p${id}`],submeter:null,difference:null,balanceQuality:'leaf',hasChildren:false,percentage:null});
  const previous=node('total','总电表',100);previous.balanceQuality='topologyUnknown';
  const total=node('total','总电表',300);Object.assign(total,{submeter:300,difference:0,hasChildren:true,balanceQuality:'ok',balanceMode:'consistency',lossEligible:false});
  const a=node('a','分电表A',100,'total'),b=node('b','分电表B',200,'total');
  const graph=(nodes:EnergyFlowNode[],known:boolean):EnergyFlowData=>({categoryId:'electric',unit:'kWh',focusId:'total',rootIds:['total'],nodes,links:known?[{source:'total',target:'a',value:100,quality:'ok',sourceIds:['pa'],percentage:100/3},{source:'total',target:'b',value:200,quality:'ok',sourceIds:['pb'],percentage:200/3}]:[],unassigned:[]});
  const segment=(from:string,to:string,nodes:EnergyFlowNode[],known:boolean)=>({from,to,known,energyFlow:graph(nodes,known),rows:nodes.map(n=>({...n,nodeId:n.id})),series:nodes.map(n=>({id:n.id,nodeId:n.id,name:n.name,categoryId:'electric',unit:'kWh',points:[{ts:from,value:n.value,quality:n.quality,sourceIds:n.sourceIds}]})),summary:{value:nodes[0].value},warnings:[]});
  const first=segment(start,change,[previous],false),second=segment(change,end,[total,a,b],true);
  const result:ReportResult={kind:'energyFlow',from:start,to:end,period:'day',rows:[...first.rows,...second.rows],series:[...first.series,...second.series],summary:{segmentCount:2},warnings:[],extra:{energyFlow:first.energyFlow,energyFlowSegments:[first,second]}};
  const overviewRows=[{id:'total',nodeId:'total',name:'总电表',unit:'kWh',value:400,quality:'ok',complete:true,coverage:1,activeSeconds:7200,coveredSeconds:7200,removed:false,substituted:false,sourceIds:['pt'],periods:[{from:start,to:end,value:400,quality:'ok',pointId:'pt'}]}];
  result.rows=overviewRows;result.series=[];result.extra!.energyFlowOverview={from:start,to:end,unknownTopologySeconds:3600,rows:overviewRows};
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{state.requests.push({path:'report',body:route.request().postDataJSON()});await route.fulfill({json:{ok:true,data:result}});});
  await openView(page,'energyFlow');
  await expect(page.getByRole('heading',{name:zh?'全区间总览':'Full period overview',exact:true})).toBeVisible();
  await expect(page.locator('[data-overview-meter="total"]')).toContainText('400');
  await expect(page.locator('.report-surface')).toContainText(start);
  if(zh&&!mobile){
   await page.getByRole('button',{name:/导出当前报表/}).hover();const pending=page.waitForEvent('download');await page.getByRole('menuitem',{name:'Excel 工作簿 (.xlsx)',exact:true}).click();
   const file=testInfo.outputPath('whole-period-overview.xlsx');await (await pending).saveAs(file);
   const zip=await JSZip.loadAsync(await readFile(file)),strings=await zip.file('xl/sharedStrings.xml')!.async('string');
   expect(strings).toContain(start);expect(strings).toContain('覆盖时段与缺口');
  }
  const select=page.getByRole('combobox',{name:zh?'计量关系时段':'Metering relationship period',exact:true});
  await select.press('ArrowDown');await page.locator('.ant-select-dropdown:visible').getByText(zh?/第 1 段：/:/Segment 1:/).click();
  await expect(page.locator('.energy-flow-notices')).toContainText(zh?'历史计量关系尚未确认':'Historical metering relationships are unconfirmed');
  await expect(page.locator('[data-flow-node="a"]')).toHaveCount(0);
  await select.press('ArrowDown');await page.locator('.ant-select-dropdown:visible').getByText(zh?/第 2 段：/:/Segment 2:/).click();
  await expect(page.locator('[data-flow-node="total"]')).toHaveAttribute('data-flow-value','300');
  await expect(page.locator('[data-flow-node="a"]')).toHaveAttribute('data-flow-value','100');
  await expect(page.locator('.energy-flow-notices')).toContainText(zh?'计算一致性检查':'Calculation consistency check');
  expect(state.requests.filter(row=>row.path==='report')).toHaveLength(1);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('historical-flow-segment.png'),fullPage:true});
  if(zh&&!mobile){
   await page.getByRole('button',{name:/导出当前报表/}).hover();const pending=page.waitForEvent('download');await page.getByRole('menuitem',{name:'Excel 工作簿 (.xlsx)',exact:true}).click();
   const download=await pending,file=testInfo.outputPath('selected-history-segment.xlsx');await download.saveAs(file);
   const zip=await JSZip.loadAsync(await readFile(file)),strings=await zip.file('xl/sharedStrings.xml')!.async('string');
   expect(strings).toContain('分电表B');expect(strings).toContain(change);expect(strings).not.toContain(start);
  }
  expect(errors).toEqual([]);
 });
});
