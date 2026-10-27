import {describe,expect,it,vi} from 'vitest';
import {createElement,type ReactNode} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {EnergyFlowView} from './EnergyFlowView';
import {energyFlowGraphs,energyFlowGraphSnapshot,energyFlowLayout,energyFlowStats,focusEnergyFlowSnapshot,type EnergyFlowData,type EnergyFlowNode} from './energyFlow';
import {makeSnapshot,reportTables} from './exports';
import type {ReportSnapshot} from './types';

vi.mock('antd',()=>({Tooltip:({children}:{children:ReactNode})=>children}));
const node=(id:string,value:number|null,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode=>({id,nodeId:id,name:id,nodeType:'meter',parentId,value,quality:value===null?'missing':'ok',categoryId:'e',unit:'kWh',sourceIds:[id+'-point'],submeter:null,difference:null,balanceQuality:'ok',hasChildren:false,percentage:null,...extra});
function graph(id:string,value:number,basis:EnergyFlowData['basis']='calculation'):EnergyFlowData{
 return {graphId:id,objectId:id,basis,additive:true,contributionMemberIds:['a'],sharedMemberIds:['a'],categoryId:'e',unit:'kWh',focusId:id,rootIds:[id],nodes:[node(id,value,undefined,{hasChildren:true}),node(id+'/a',40,id,{nodeId:'a',name:'业务电表 A'})],links:[{source:id,target:id+'/a',value:40,quality:'ok',sourceIds:['a-point'],percentage:null,relationKind:'calculation'}],unassigned:[]};
}
function source():ReportSnapshot{
 const q={kind:'energyFlow' as const,dimension:'metering' as const,nodeIds:['t','g1','g2'],categoryId:'e',from:'2026-10-01T00:00:00+08:00',to:'2026-10-27T10:00:00+08:00',metric:'energy' as const,period:'day' as const,perArea:false};
 const graphs=[graph('t',110,'metering'),graph('g1',40),graph('g2',100)];
 return makeSnapshot(q,{kind:'energyFlow',from:q.from,to:q.to,period:'day',series:[],rows:[],summary:{},warnings:[],extra:{relationBasis:'current',energyFlow:graphs[0],energyFlowGraphs:graphs,energyFlowAccounting:{canAdd:false,memberIds:['a','b'],sharedMemberIds:['a'],sharedMembers:[{meterId:'a',objectIds:['g1','g2']}],unionValue:null,unionQuality:'overlappingScopes',basis:'unavailable'}}},'Flow','cubeTest');
}
describe('current energy-flow object graphs',()=>{
 it('keeps an empty valid graph unavailable without inventing consumption',()=>{
  const original=source(),data=graph('empty',0);data.nodes=[];data.links=[];original.result.extra!.energyFlowGraphs=[data];
  const selected=energyFlowGraphSnapshot(original,'empty');expect(selected.result.summary.value).toBeNull();expect(selected.result.rows).toEqual([]);
 });
 it('keeps independent physical and overlapping virtual results separate',()=>{
  const snapshot=source(),before=structuredClone(snapshot);
  expect(energyFlowGraphs(snapshot.result).map(item=>item.nodes[0].value)).toEqual([110,40,100]);
  const g2=energyFlowGraphSnapshot(snapshot,'g2');
  expect(g2.result.rows.map(row=>row.name)).toEqual(['g2','业务电表 A']);
  expect(reportTables(g2).rows.flat()).toContain('100');
  expect(JSON.stringify(g2.result.extra)).not.toContain('"objectId":"t"');
  expect(snapshot).toEqual(before);
 });
 it('uses available node amounts in the graph without filling a missing sibling with zero',()=>{
  const data=graph('t',100,'metering');
  data.nodes[0]={...data.nodes[0],value:null,knownValue:100,knownQuality:'filtered'};
  data.nodes.push(node('missing',null,'t'));
  expect(energyFlowStats(data).total).toBe(100);
  expect(energyFlowLayout(data).links).toHaveLength(1);
  expect(data.nodes.find(item=>item.id==='missing')!.value).toBeNull();
 });
 it('uses the server child subtotal instead of adding repeated displayed references',()=>{
  const data=graph('t',110,'metering');data.nodes[0].knownSubmeter=40;
  data.nodes.push(node('t/a-again',40,'t',{nodeId:'a'}));
  expect(energyFlowStats(data).submeter).toBe(40);
  const original=source();original.result.extra!.energyFlowGraphs=[data];
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:energyFlowGraphSnapshot(original,'t'),exporting:false,onFocus:()=>{}}));
  expect(html).toContain('下级已有用量小计</span><strong>40');
 });
 it('can drill a space group locally and return only to its selected graph root',()=>{
  const original=source();const data=graph('floor',40,'space');
  data.nodes[0].nodeType='space';data.nodes[1].nodeType='space';data.nodes[1].hasChildren=true;
  data.nodes.push(node('floor/a/meter',40,'floor/a'));
  original.result.extra!.energyFlowGraphs=[data];
  const selected=energyFlowGraphSnapshot(original,'floor');
  const focused=focusEnergyFlowSnapshot(selected,'floor/a');
  expect(focused.request.nodeIds).toEqual(['a']);
  expect(focusEnergyFlowSnapshot(focused,'').result.extra!.energyFlow).toEqual(data);
 });
 it('isolates occurrences when a nested classification references the same meter twice',()=>{
  const original=source(),data=graph('nested',80);data.nodes=[node('nested',80,undefined,{hasChildren:true}),node('nested/one',40,'nested',{nodeId:'one',hasChildren:true}),node('nested/one/a',40,'nested/one',{nodeId:'a'}),node('nested/two',40,'nested',{nodeId:'two',hasChildren:true}),node('nested/two/a',40,'nested/two',{nodeId:'a'})];
  original.result.extra!.energyFlowGraphs=[data];
  const selected=energyFlowGraphSnapshot(original,'nested'),focused=focusEnergyFlowSnapshot(selected,'nested/one');
  expect(focused.result.rows.map(row=>row.id)).toEqual(['nested/one','nested/one/a']);
  expect(focused.result.series.map(row=>row.id)).toEqual(['nested/one','nested/one/a']);
 });
 it('labels space distribution as statistics without physical leakage cards',()=>{
  const original=source(),data=graph('floor',40,'space');data.nodes[0].nodeType='space';
  original.result.extra!.energyFlowGraphs=[data];
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:energyFlowGraphSnapshot(original,'floor'),exporting:false,onFocus:()=>{}}));
  expect(html).toContain('空间能耗分布');expect(html).toContain('统计汇总');
  expect(html).not.toContain('直属分表合计');expect(html).not.toContain('计量差额');
 });
 it('preserves weighted calculation values and explains references without conservation',()=>{
  const original=source(),data=graph('weighted',80);data.additive=false;data.nodes[1].percentage=50;
  original.result.extra!.energyFlowGraphs=[data];
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:energyFlowGraphSnapshot(original,'weighted'),exporting:false,onFocus:()=>{}}));
  expect(html).toContain('data-flow-value="80"');expect(html).toContain('公式引用');
  expect(html).not.toContain('直属分表合计');
  expect(html).not.toContain('50%');
 });
});
