import {test,expect,type Page} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView} from './fixtures';
import type {EnergyFlowData,EnergyFlowNode} from '../../src/energyFlow';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

const names:Record<string,string>={t:'物理总表',a:'业务分表 A',b:'业务分表 B',g1:'动力分类',g2:'重点分类',site:'测试站点',floor:'测试楼层',org:'测试公司',dept:'测试部门'};
const node=(id:string,value:number|null,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode=>({id,nodeId:id,name:names[id]||id,parentId,nodeType:'meter',categoryId:'e',unit:'kWh',value,quality:value===null?'missing':'ok',sourceIds:[id+'-point'],submeter:null,difference:null,balanceQuality:'missing',hasChildren:false,percentage:null,...extra});
function graph(id:string,basis:EnergyFlowData['basis']):EnergyFlowData{
 const grouped=basis==='space'||basis==='organization',members=id==='g1'?['a']:['a','b'],child=grouped?(basis==='space'?'floor':'dept'):undefined;
 const root=node(id,id==='t'?null:id==='g1'?40:100,undefined,{...(id==='t'?{knownValue:110,knownQuality:'filtered'}:{}),nodeType:grouped?basis:'meter',hasChildren:true,coveredSeconds:3600,activeSeconds:7200,coverage:.5});
 const children=members.map(member=>node(id+'/'+member,member==='a'?40:60,child?id+'/'+child:id,{nodeId:member,name:names[member],coveredSeconds:3600,coverage:.5}));
 const nodes=[root,...(child?[node(id+'/'+child,100,id,{nodeId:child,name:names[child],nodeType:basis as 'space'|'organization',hasChildren:true})]:[]),...children];
 const links=nodes.filter(item=>item.parentId).map(item=>({source:item.parentId!,target:item.id,value:item.knownValue??item.value??0,quality:item.quality,sourceIds:item.sourceIds,percentage:null,relationKind:grouped?'grouping' as const:basis==='calculation'?'calculation' as const:'metering' as const}));
 return {graphId:id,objectId:id,basis,categoryId:'e',unit:'kWh',focusId:id,rootIds:[id],nodes,links,unassigned:[],additive:true,contributionMemberIds:members,sharedMemberIds:grouped?[]:['a']};
}
function result(request:ReportRequest):ReportResult{
 const grouped=request.dimension==='space'||request.dimension==='organization';
 const graphs=request.nodeIds.map(id=>graph(id,grouped?request.dimension as 'space'|'organization':id==='t'?'metering':'calculation'));
 const mixed=!grouped&&request.nodeIds.includes('t');
 return {kind:'energyFlow',from:request.from,to:request.to,period:'day',asOf:request.to,rows:graphs.flatMap(graph=>graph.nodes.map(node=>({...node,graphId:graph.graphId}))),series:[],warnings:[],summary:{},extra:{relationBasis:'current',usageBasis:'knownUsage',energyFlow:graphs[0],energyFlowGraphs:graphs,energyFlowOverview:{from:request.from,to:request.to,unknownTopologySeconds:0,rows:[]},energyFlowAccounting:{canAdd:grouped,memberIds:['a','b'],sharedMemberIds:grouped?[]:['a'],sharedMembers:grouped?[]:[{meterId:'a',objectIds:['g1','g2']}],unionValue:mixed?null:100,unionQuality:'filtered',basis:mixed?'unavailable':grouped?'physicalBoundary':'classificationUnion'}}};
}
async function select(page:Page,ids:string[]){
 await page.locator('.object-select-button').click();
 for(const id of ids)await page.locator('.object-panel .ant-tree-treenode').filter({hasText:names[id]}).first().locator('.ant-tree-checkbox').click();
 await page.locator('.object-selector-drawer .ant-drawer-footer button').click();
}
for(const language of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`current flow ${language} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale:language,viewport:mobile?{width:390,height:844}:{width:1440,height:1000}});
 test('manually queries separate object graphs, exposes overlap and changes grouping perspective',async({page},testInfo)=>{
  const zh=language==='zh-CN';await page.clock.setFixedTime(new Date('2026-10-27T02:00:00Z'));
  const records:EnerCubixRecord[]=[{id:'e',kind:'category',name:'电能',unit:'kWh'},...['site','floor'].map(id=>({id,kind:'space' as const,name:names[id],parentId:id==='floor'?'site':undefined})),...['org','dept'].map(id=>({id,kind:'organization' as const,name:names[id],parentId:id==='dept'?'org':undefined})),...['t','a','b','g1','g2'].map(id=>({id,kind:id==='t'?'totalMeter' as const:'meter' as const,name:names[id],categoryId:'e',unit:'kWh',pointId:id+'-point',meterParentId:['a','b'].includes(id)?'t':undefined,spaceId:'floor',organizationId:'dept',includeInTotals:!id.startsWith('g')}))];
  const state=await installTransport(page,{records});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{const request=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:request as unknown as Record<string,unknown>});await route.fulfill({json:{ok:true,data:result(request)}});});
  await openView(page,'energyFlow');
  await expect(page.locator('.object-select-button')).toBeVisible();await expect(page.locator('.filter-actions button').first()).toBeDisabled();
  expect(state.requests.filter(row=>row.path==='report')).toHaveLength(0);
  await page.locator('.report-dimension-select .ant-radio-button-wrapper').filter({hasText:zh?'计量':'Metering'}).click();await select(page,['t','g1','g2']);
  await page.locator('.filter-actions button').first().click();
  await expect(page.locator('.energy-flow-current')).toHaveCount(3);
  await expect(page.locator('[data-flow-graph="t"] [data-flow-node="t"]')).toHaveAttribute('data-flow-value','110');
  await expect(page.locator('[data-flow-graph="g1"] [data-flow-node="g1"]')).toHaveAttribute('data-flow-value','40');
  await expect(page.locator('[data-flow-graph="g2"] [data-flow-node="g2"]')).toHaveAttribute('data-flow-value','100');
  await expect(page.locator('.energy-flow-accounting')).toContainText(zh?'没有统一统计边界':'no common accounting boundary');
  await expect(page.locator('.energy-flow-accounting')).toContainText(names.a);
  await expect(page.locator('[data-flow-graph="g2"] .energy-flow-reference')).toHaveCount(2);
  await expect(page.getByRole('combobox',{name:zh?'计量关系时段':'Metering relationship period',exact:true})).toHaveCount(0);
  expect(state.requests.filter(row=>row.path==='report')[0].body).toMatchObject({dimension:'metering',nodeIds:['t','g1','g2'],from:'2026-10-01T00:00:00+08:00',to:'2026-10-27T10:00:00+08:00'});
  await page.locator('.object-select-button').click();await page.locator('.object-panel .ant-tree-treenode').filter({hasText:names.t}).first().locator('.ant-tree-checkbox').click();await page.locator('.object-selector-drawer .ant-drawer-footer button').click();await page.locator('.filter-actions button').first().click();
  await expect(page.locator('.energy-flow-current')).toHaveCount(2);await expect(page.locator('.energy-flow-accounting')).toContainText(zh?'分类去重贡献合计：100':'Deduplicated classification contribution: 100');
  await page.getByRole('button',{name:zh?/导出当前报表/:/Export current report/}).hover();const pending=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();const downloaded=testInfo.outputPath('current-classification.xlsx');await(await pending).saveAs(downloaded);const zip=await JSZip.loadAsync(await readFile(downloaded));const strings=await zip.file('xl/sharedStrings.xml')!.async('string');expect(strings).toContain(names.g1);expect(strings).toContain(names.g2);expect(strings).toContain(names.a);
  for(const dimension of ['space','organization'] as const){await page.locator('.report-dimension-select .ant-radio-button-wrapper').filter({hasText:dimension==='space'?(zh?'空间':'Space'):(zh?'组织':'Organization')}).click();await select(page,[dimension==='space'?'site':'org']);await page.locator('.filter-actions button').first().click();const panel=page.locator('.energy-flow-current');await expect(panel).toHaveCount(1);await expect(panel).toContainText(dimension==='space'?(zh?'空间能耗分布':'Space energy distribution'):(zh?'组织能耗分布':'Organization energy distribution'));await expect(panel.getByText(zh?'计量差额':'Metering difference',{exact:true})).toHaveCount(0);await panel.locator('.energy-flow-node-action').first().click();await expect(panel.locator('.energy-flow-path')).toContainText(dimension==='space'?names.floor:names.dept);await panel.getByRole('button',{name:zh?'返回所选范围':'Back to selected scope',exact:true}).click();await expect(panel.locator('.energy-flow-path')).toContainText(dimension==='space'?names.site:names.org);}
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('current-energy-flow.png'),fullPage:true});
 });
});
