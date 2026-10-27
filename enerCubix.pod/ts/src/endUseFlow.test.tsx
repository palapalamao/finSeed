import {describe,expect,it,vi} from 'vitest';
import {createElement,type ReactNode} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {EnergyFlowView} from './EnergyFlowView';
import {EnergyFlowGraphsView} from './EnergyFlowGraphsView';
import {energyFlowLayout,type EnergyFlowData,type EnergyFlowNode} from './energyFlow';
import {applyKnownUsageDisplay} from './usageDisplay';
import type {ReportSnapshot} from './types';
vi.mock('antd',()=>({Tooltip:({children}:{children:ReactNode})=>children}));
const node=(id:string,value:number,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode=>({id,nodeId:id,name:id,nodeType:'meter',parentId,value,quality:'ok',categoryId:'e',unit:'kWh',sourceIds:[id],submeter:null,difference:null,balanceQuality:'ok',hasChildren:false,percentage:null,...extra});
describe('end-use flow presentation',()=>{
 it('identifies end-use grouping and keeps the measured master separate from distribution',()=>{
  const graph={graphId:'endUse|m',basis:'endUse',focusId:'m',rootIds:['m'],categoryId:'e',unit:'kWh',contributionMemberIds:['a','b'],nodes:[node('m',1000,undefined,{hasChildren:true,submeter:900,difference:100}),node('lighting',400,'m',{nodeType:'utility',utilityId:'lighting',hasChildren:true,memberIds:['a']}),node('power',500,'m',{nodeType:'utility',utilityId:'power',hasChildren:true,memberIds:['b']}),node('a',400,'lighting'),node('b',500,'power')],links:[{source:'m',target:'lighting',value:400,quality:'ok',sourceIds:['a'],percentage:40,relationKind:'classification'},{source:'m',target:'power',value:500,quality:'ok',sourceIds:['b'],percentage:50,relationKind:'classification'}],unassigned:[]} as EnergyFlowData;
  const from='2026-10-01T00:00:00+08:00',to='2026-10-02T00:00:00+08:00';
  const s:ReportSnapshot={title:'Flow',project:'cubeTest',generatedAt:from,request:{kind:'energyFlow',flowMode:'endUse',dimension:'metering',nodeIds:['m'],categoryId:'e',from,to,period:'day',metric:'energy',perArea:false},result:{kind:'energyFlow',from,to,period:'day',warnings:[],summary:{},series:[],rows:[],extra:{energyFlow:graph}}};
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:s,exporting:false,onFocus:()=>{}}));
  expect(html).toContain('分项能流');expect(html).toContain('分项已有用量合计');expect(html).toContain('表计数量');expect(html).not.toContain('直属分表数量');expect(html).toContain('1,000');expect(html).toContain('900');
  expect(energyFlowLayout(graph).links.map(row=>row.link.value)).toEqual([400,500]);
  s.result.extra!.energyFlowAccounting={canAdd:true,memberIds:['a','b'],sharedMemberIds:[],sharedMembers:[],unionValue:900,unionQuality:'ok',basis:'physicalBoundary'};
  const panels=renderToStaticMarkup(createElement(EnergyFlowGraphsView,{snapshot:s,panels:[s],exporting:false,onFocus:()=>{}}));
  expect(panels).toContain('范围分项已有合计（已去重）');
  expect(panels).toContain('总表自身用量在各图中单独展示');
 });
 it('uses the same available own-meter values in member details and exports',()=>{
  const result={kind:'utility' as const,from:'a',to:'b',period:'day' as const,summary:{},warnings:[],series:[],rows:[],extra:{utilityMembers:[{nodeId:'a',utilityId:'lighting',value:null,knownValue:9,quality:'missing',knownQuality:'filtered'}]}};
  applyKnownUsageDisplay(result);
  expect(result.extra.utilityMembers[0]).toMatchObject({value:9,completeValue:null,quality:'filtered'});
 });
});
