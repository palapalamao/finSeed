import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport} from './fixtures';
import type {EnergyFlowNode,EnergyFlowData} from '../../src/energyFlow';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

for(const en of [false,true])test(`site scope removes repeated floors and separates references in ${en?'English':'Chinese'}`,async({page},info)=>{
 const names={site:en?'Campus':'园区',f1:en?'Floor 1':'一层',f2:en?'Floor 2':'二层',summary:en?'Incoming meter floor':'进线表楼层',t:en?'Site main':'站点总表',a:en?'Floor 1 main':'一层总表',b:en?'Floor 2 main':'二层总表',child:en?'Lighting':'照明表'};
 const request:ReportRequest={kind:'energyFlow',dimension:'space',nodeIds:['site','f1','f2'],categoryId:'e',from:'2026-10-01T00:00:00+08:00',to:'2026-10-02T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
 const records:EnerCubixRecord[]=[{id:'e',kind:'category',name:en?'Electricity':'电能',unit:'kWh'},...['site','f1','f2','summary'].map(id=>({id,kind:'space' as const,name:names[id as keyof typeof names],parentId:id==='site'?undefined:'site'})),{id:'template',kind:'template',name:en?'Whole site':'整个站点',request}];
 const n=(id:keyof typeof names,value:number,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode=>({id,nodeId:id,name:names[id],nodeType:'meter',parentId,value,knownValue:value,quality:'ok',knownQuality:'ok',categoryId:'e',unit:'kWh',sourceIds:[id+'-point'],submeter:null,difference:null,balanceQuality:'ok',hasChildren:false,percentage:null,...extra});
 const nodes=[n('site',500,undefined,{nodeType:'space',hasChildren:true,distributionComparable:false,knownSubmeter:900}),n('f1',600,'site',{nodeType:'space',hasChildren:true,distributionComparable:true}),n('a',600,'f1',{referenceOnly:true}),n('child',600,'f1'),n('f2',300,'site',{nodeType:'space',hasChildren:true}),n('b',300,'f2'),n('summary',500,'site',{nodeType:'space',referenceOnly:true,hasChildren:true}),n('t',500,'summary')];
 const graph:EnergyFlowData={graphId:'space|site',objectId:'site',basis:'space',categoryId:'e',unit:'kWh',focusId:'site',rootIds:['site'],nodes,links:[{source:'f1',target:'child',value:600,quality:'ok',sourceIds:['child-point'],percentage:null,relationKind:'grouping'}],unassigned:[],contributionMemberIds:['t'],additive:true,boundaryQuality:'ok'};
 const result:ReportResult={kind:'energyFlow',from:request.from,to:request.to,period:'day',asOf:request.to,series:[],rows:nodes.map(node=>({...node})),summary:{},warnings:[],extra:{relationBasis:'current',energyFlow:graph,energyFlowGraphs:[graph],energyFlowCoveredScopes:['f1','f2'].map(id=>({id,name:names[id as 'f1'|'f2']}))}};
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));

 const state=await installTransport(page,{userLocale:en?'en-US':'zh-CN',records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{state.requests.push({path:'report',body:route.request().postDataJSON()});await route.fulfill({json:{ok:true,data:result}});});
 await page.goto('/#/energyFlow?project=testproject&template=template');await page.getByRole('button',{name:en?'Query':'查询',exact:true}).click();
 const panel=page.locator('.energy-flow-current');await expect(panel).toHaveCount(1);
 await expect(page.getByRole('status').filter({hasText:en?'Selections already covered':'已合并被上级范围包含'})).toContainText(names.f1);
 await expect(panel.locator('[data-flow-node="summary"]')).toHaveCount(0);await expect(panel.locator('[data-flow-node="a"]')).toHaveCount(0);
 await expect(panel.locator('[data-flow-reference="summary"]')).toContainText('500');await expect(panel.locator('[data-flow-reference="a"]')).toContainText('600');
 await expect(panel.locator('.energy-flow-ribbon[data-flow-source="site"]')).toHaveCount(0);
 await expect(panel.locator('.energy-flow-reference[data-flow-source="site"]')).toHaveCount(2);
 await panel.locator('[data-flow-node="f1"]').click();await expect(panel.locator('.energy-flow-path')).toContainText(names.f1);
 await panel.getByRole('button',{name:en?'Back to selected scope':'返回所选范围',exact:true}).click();
 await panel.locator('[data-flow-reference="summary"] button').click();await expect(panel.locator('[data-flow-node="t"]')).toBeVisible();
 await panel.getByRole('button',{name:en?'Back to selected scope':'返回所选范围',exact:true}).click();
 expect(state.requests.filter(item=>item.path==='report')).toHaveLength(1);
 for(const width of [1440,390]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:info.outputPath(`site-${en?'en':'zh'}-${width}.png`),fullPage:true});}
 await page.getByRole('button',{name:en?/Export current report/:/导出当前报表/}).hover();const download=page.waitForEvent('download');await page.getByRole('menuitem',{name:en?'Excel workbook (.xlsx)':'Excel 工作簿 (.xlsx)',exact:true}).click();const file=info.outputPath('site-scope.xlsx');await(await download).saveAs(file);const zip=await JSZip.loadAsync(await readFile(file));const strings=await zip.file('xl/sharedStrings.xml')!.async('string');expect(strings).toContain(names.summary);expect(strings).toContain(en?'Summary reference only':'仅作汇总参考');expect(errors).toEqual([]);
});
