import type {Page} from '@playwright/test';
import type {EnergyFlowData,EnergyFlowLink,EnergyFlowNode} from '../../src/energyFlow';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';
import {installTransport,openView} from './fixtures';

export const summaryId='__energyFlow__:electric';
export const differenceId=(id:string)=>`__energyFlowDifference__:${id}`;

function node(id:string,name:string,value:number|null,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode{
 return {id,name,value,parentId,nodeType:'meter',categoryId:'electric',unit:'kWh',quality:value===null?'missing':'ok',sourceIds:['point1'],submeter:null,difference:null,balanceQuality:'leaf',hasChildren:false,percentage:null,...extra};
}

function electricFlow(abnormal:boolean):EnergyFlowData{
 const total=abnormal?1500:1800;
 const nodes=[
  node(summaryId,'能源汇总',total,undefined,{nodeType:'summary',quality:'derived',sourceIds:['point1','point2'],hasChildren:true,submeter:total,difference:0,balanceQuality:'ok'}),
  node('a','东楼总表',1000,undefined,{sourceIds:['point2'],hasChildren:true,submeter:800,difference:200,balanceQuality:'ok',percentage:1000/total*100}),
  node('a1','东楼空调分表',600,'a',{hasChildren:true,submeter:abnormal?null:500,difference:abnormal?null:100,balanceQuality:abnormal?'missing':'ok',percentage:60}),
  node('a11','机房冷机',abnormal?null:400,'a1',{percentage:abnormal?null:400/600*100}),
  node('a12','机房水泵',100,'a1',{percentage:abnormal?null:100/600*100}),
  node('a2','东楼照明分表',200,'a',{percentage:20}),
  // A real business name deliberately matches the synthetic summary label.
  node('b','能源汇总',abnormal?500:800,undefined,{hasChildren:true,submeter:600,difference:abnormal?-100:200,balanceQuality:abnormal?'negativeBalance':'ok',percentage:(abnormal?500:800)/total*100}),
  node('b1','西楼照明分表',600,'b',{percentage:abnormal?null:75}),
  node(differenceId('a'),'计量差额',200,'a',{nodeType:'difference',quality:'derived',percentage:20}),
  ...(!abnormal?[
   node(differenceId('a1'),'计量差额',100,'a1',{nodeType:'difference',quality:'derived',percentage:100/600*100}),
   node(differenceId('b'),'计量差额',200,'b',{nodeType:'difference',quality:'derived',percentage:25})
  ]:[])
 ];
 const byId=new Map(nodes.map(item=>[item.id,item]));
 const edge=(source:string,target:string):EnergyFlowLink=>{const targetNode=byId.get(target)!;return {source,target,value:targetNode.value!,quality:targetNode.quality,sourceIds:targetNode.sourceIds,percentage:targetNode.percentage};};
 const links=[edge(summaryId,'a'),edge(summaryId,'b'),edge('a','a1'),edge('a','a2'),edge('a',differenceId('a')),
  ...(!abnormal?[edge('a1','a11'),edge('a1','a12'),edge('a1',differenceId('a1')),edge('b','b1'),edge('b',differenceId('b'))]:[])];
 return {categoryId:'electric',unit:'kWh',focusId:summaryId,rootIds:['a','b'],nodes,links,unassigned:[node('orphan','未挂接电表',91)]};
}

function waterFlow():EnergyFlowData{
 const summary='__energyFlow__:water';
 const nodes=[
  node(summary,'能源汇总',120,undefined,{nodeType:'summary',hasChildren:true,quality:'derived',submeter:120,difference:0,balanceQuality:'ok'}),
  node('water-main','生活水总表',120,undefined,{hasChildren:true,submeter:90,difference:30,balanceQuality:'ok',percentage:100}),
  node('water-branch','生活水分表',90,'water-main',{percentage:75}),
  node(differenceId('water-main'),'计量差额',30,'water-main',{nodeType:'difference',quality:'derived',percentage:25})
 ].map(item=>({...item,categoryId:'water',unit:'m³'}));
 const links=[{source:summary,target:'water-main',value:120,percentage:100},{source:'water-main',target:'water-branch',value:90,percentage:75},{source:'water-main',target:differenceId('water-main'),value:30,percentage:25}].map(item=>({...item,quality:'ok',sourceIds:['point1']}));
 return {categoryId:'water',unit:'m³',focusId:summary,rootIds:['water-main'],nodes,links,unassigned:[]};
}

function resultForFlow(request:ReportRequest,abnormal:boolean):ReportResult{
 const data=request.categoryId==='water'?waterFlow():electricFlow(abnormal);
 const focus=request.nodeIds[0]==='flow-scope'?undefined:request.nodeIds[0];
 if(focus){
  const ids=new Set([focus]);let previous=0;
  while(previous!==ids.size){previous=ids.size;for(const item of data.nodes)if(item.parentId&&ids.has(item.parentId))ids.add(item.id);}
  data.focusId=focus;data.rootIds=[focus];data.nodes=data.nodes.filter(item=>ids.has(item.id));
  data.links=data.links.filter(link=>ids.has(link.source)&&ids.has(link.target));data.unassigned=[];
 }
 const all=[...data.nodes,...data.unassigned];
 return {kind:'energyFlow',from:request.from,to:request.to,period:'day',warnings:[],summary:{total:data.nodes[0].value},
  rows:all.map(item=>({...item,nodeId:item.id})),
  series:all.map(item=>({id:item.id,nodeId:item.id,name:item.name,categoryId:item.categoryId,unit:item.unit,points:[{ts:request.from,value:item.value,quality:item.quality,sourceIds:item.sourceIds}]})),extra:{energyFlow:data}};
}

export async function setupEnergyFlow(page:Page,{abnormal=false,query=true}={}){
 const data=electricFlow(abnormal);
 const records:EnerCubixRecord[]=[{id:'flow-scope',kind:'space',name:'测试范围'}, {id:'electric',kind:'category',name:'测试电能',unit:'kWh'},{id:'water',kind:'category',name:'测试水量',unit:'m³'},
  ...[...data.nodes,...data.unassigned,...waterFlow().nodes].filter(item=>item.nodeType==='meter').map(item=>({id:item.id,mod:'m1',kind:(data.rootIds.includes(item.id)||item.id==='water-main'?'totalMeter':'meter') as 'totalMeter'|'meter',name:item.name,categoryId:item.categoryId,unit:item.unit,pointId:item.sourceIds[0],meterParentId:item.parentId,spaceId:'flow-scope',includeInTotals:true}))];
 const state=await installTransport(page,{records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const request=route.request().postDataJSON() as ReportRequest;
  state.requests.push({path:'report',body:request as unknown as Record<string,unknown>});
  await route.fulfill({json:{ok:true,data:resultForFlow(request,abnormal)}});
 });
 await openView(page,'energyFlow');
 if(query)await selectEnergyFlowScope(page);
 return state;
}

export async function selectEnergyFlowScope(page:Page){
 await page.locator('.object-select-button').click();
 await page.locator('.object-panel .ant-tree-treenode').filter({hasText:'测试范围'}).first().locator('.ant-tree-checkbox').click();
 await page.locator('.object-selector-drawer .ant-drawer-footer button').click();
 await page.locator('.filter-actions button').first().click();
}
