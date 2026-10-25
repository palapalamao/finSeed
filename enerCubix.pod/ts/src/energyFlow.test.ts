import {describe,expect,it,vi} from 'vitest';
import {createElement,type ReactNode} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {EnergyFlowView} from './EnergyFlowView';
import {defaultEnergyFlowSegment,energyFlowBreadcrumbs,energyFlowData,energyFlowLayout,energyFlowStats,energyFlowSegments,energyFlowSegmentSnapshot,focusEnergyFlowSnapshot,type EnergyFlowData,type EnergyFlowNode} from './energyFlow';
import type {ReportSnapshot} from './types';

// Browser coverage exercises the actual tooltip. These server-rendering checks inspect chart content.
vi.mock('antd',()=>({Tooltip:({children}:{children:ReactNode})=>children}));

const summaryId='__energyFlow__:electric';
function node(id:string,value:number|null,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode{
 return {id,name:id,nodeType:'meter',parentId,categoryId:'electric',unit:'kWh',value,quality:value===null?'missing':'ok',sourceIds:[`point-${id}`],submeter:null,difference:null,balanceQuality:'ok',hasChildren:false,percentage:null,...extra};
}
function snapshot():ReportSnapshot{
 const nodes=[node(summaryId,180,undefined,{nodeType:'summary',hasChildren:true,submeter:180,difference:0}),node('a',100,undefined,{name:'能源汇总',hasChildren:true,submeter:80,difference:20,percentage:100/180*100}),node('a1',60,'a',{hasChildren:true,submeter:50,difference:10,percentage:60}),node('a11',50,'a1',{percentage:50/60*100}),node('__energyFlowDifference__:a1',10,'a1',{nodeType:'difference',percentage:10/60*100}),node('a2',20,'a',{percentage:20}),node('__energyFlowDifference__:a',20,'a',{nodeType:'difference',percentage:20}),node('b',80,undefined,{percentage:80/180*100})];
 const data:EnergyFlowData={categoryId:'electric',unit:'kWh',focusId:summaryId,rootIds:['a','b'],nodes,links:[{source:summaryId,target:'a',value:100,quality:'ok',sourceIds:['point-a'],percentage:100/180*100},{source:summaryId,target:'b',value:80,quality:'ok',sourceIds:['point-b'],percentage:80/180*100},{source:'a',target:'a1',value:60,quality:'ok',sourceIds:['point-a1'],percentage:60},{source:'a',target:'a2',value:20,quality:'ok',sourceIds:['point-a2'],percentage:20},{source:'a',target:'__energyFlowDifference__:a',value:20,quality:'derived',sourceIds:['point-a','point-a1','point-a2'],percentage:20}],unassigned:[node('orphan',500)]};
 const all=[...nodes,...data.unassigned];
 return {title:'Flow',project:'test',generatedAt:'2026-10-23T00:00:00Z',request:{kind:'energyFlow',categoryId:'electric',nodeIds:[],dimension:'metering',metric:'energy',perArea:false,period:'day',from:'2026-10-01T00:00:00Z',to:'2026-10-23T00:00:00Z'},result:{kind:'energyFlow',from:'2026-10-01T00:00:00Z',to:'2026-10-23T00:00:00Z',period:'day',warnings:[],summary:{},rows:all.map(n=>({...n,nodeId:n.id})),series:all.map(n=>({id:n.id,nodeId:n.id,name:n.name,unit:n.unit,points:[{ts:'2026-10-01',value:n.value,quality:n.quality,sourceIds:n.sourceIds}]})),extra:{energyFlow:data}}};
}

describe('energy flow snapshot scope',()=>{
 it('defaults to the full requested range when an own-history overview is supplied and scopes segment exports',()=>{
  const original=snapshot();original.result.extra!.energyFlowOverview={from:original.result.from,to:original.result.to,unknownTopologySeconds:3600,rows:[]};
  original.result.extra!.energyFlowSegments=[{from:'2026-10-10T00:00:00Z',to:original.result.to,known:true,energyFlow:energyFlowData(original.result),rows:[],series:[],summary:{},warnings:[]}];
  expect(defaultEnergyFlowSegment(original.result)).toBe(-1);
  expect(energyFlowSegmentSnapshot(original,0).result.extra).not.toHaveProperty('energyFlowOverview');
  expect(original.result.from).toBe('2026-10-01T00:00:00Z');
 });
 it('defaults to the longest complete period and retains valid zero consumption',()=>{
  const original=snapshot(),data=energyFlowData(original.result)!;
  const segment=(from:string,to:string,known:boolean,quality='ok',value:number|null=0)=>({from,to,known,energyFlow:{...data,nodes:[node('total',value,undefined,{quality})],rootIds:['total'],focusId:'total'},rows:[],series:[],summary:{},warnings:[]});
  original.result.extra!.energyFlowSegments=[segment('2026-10-25T00:00:00Z','2026-10-25T05:00:00Z',false),segment('2026-10-25T05:00:00Z','2026-10-25T06:00:00Z',true),segment('2026-10-25T06:00:00Z','2026-10-25T10:00:00Z',true,'filtered',30),segment('2026-10-25T10:00:00Z','2026-10-25T12:00:00Z',true)];
  expect(defaultEnergyFlowSegment(original.result)).toBe(3);
 });
 it('does not attach whole-query cleaning diagnostics to a selected subperiod',()=>{
  const original=snapshot();original.result.extra!.cleaning=[{summary:{coverage:.5}}];
  original.result.extra!.energyFlowSegments=[{from:'2026-10-10T00:00:00Z',to:original.result.to,known:true,energyFlow:energyFlowData(original.result),rows:original.result.rows,series:original.result.series,summary:{},warnings:[]}];
  expect(energyFlowSegmentSnapshot(original,0).result.extra).not.toHaveProperty('cleaning');
  expect(original.result.extra).toHaveProperty('cleaning');
 });
 it('selects one historical relationship segment for chart, details and exports without changing source data',()=>{
  const original=snapshot();const later=focusEnergyFlowSnapshot(snapshot(),'a1');
  original.result.extra!.energyFlowSegments=[{from:original.result.from,to:'2026-10-10T00:00:00Z',known:false,energyFlow:energyFlowData(original.result),rows:original.result.rows,series:original.result.series,summary:original.result.summary,warnings:['unknown']},{from:'2026-10-10T00:00:00Z',to:original.result.to,known:true,energyFlow:energyFlowData(later.result),rows:later.result.rows,series:later.result.series,summary:later.result.summary,warnings:[]}];
  const before=structuredClone(original),selected=energyFlowSegmentSnapshot(original,1);
  expect(energyFlowSegments(original.result)).toHaveLength(2);
  expect(selected.request.from).toBe('2026-10-10T00:00:00Z');expect(selected.result.from).toBe(selected.request.from);
  expect(selected.result.rows).toEqual(later.result.rows);expect(selected.result.series).toEqual(later.result.series);
  expect(energyFlowData(selected.result)?.focusId).toBe('a1');
  expect(selected.result.extra).not.toHaveProperty('energyFlowSegments');expect(original).toEqual(before);
 });
 it('accepts the object contract and leaves old or malformed responses unavailable',()=>{
  const original=snapshot();expect(energyFlowData(original.result)?.nodes).toHaveLength(8);
  expect(energyFlowData({...original.result,extra:{energyFlow:[]}})).toBeUndefined();
  expect(energyFlowData({...original.result,extra:undefined})).toBeUndefined();
 });
 it('scopes graph, rows, series and request to a complete selected subtree without changing values',()=>{
  const original=snapshot(),before=structuredClone(original);const focused=focusEnergyFlowSnapshot(original,'a1');
  const ids=['a1','a11','__energyFlowDifference__:a1'];
  expect(energyFlowData(focused.result)?.nodes.map(n=>n.id)).toEqual(ids);
  expect(focused.result.rows.map(row=>row.id)).toEqual(ids);expect(focused.result.series.map(s=>s.nodeId)).toEqual(ids);
  expect(focused.request.nodeIds).toEqual(['a1']);expect(energyFlowData(focused.result)?.rootIds).toEqual(['a1']);
  expect(energyFlowData(focused.result)?.unassigned).toEqual([]);expect(original).toEqual(before);
  expect(energyFlowData(focused.result)?.nodes[0].value).toBe(60);
 });
 it('retains ancestors for breadcrumbs and restores overview after nested local navigation',()=>{
  const original=snapshot();const focused=focusEnergyFlowSnapshot(focusEnergyFlowSnapshot(original,'a'),'a1');
  expect(energyFlowBreadcrumbs(focused).map(n=>n.id)).toEqual([summaryId,'a','a1']);
  const overview=focusEnergyFlowSnapshot(focused,'');
  expect(energyFlowData(overview.result)?.focusId).toBe(summaryId);expect(energyFlowData(overview.result)?.rootIds).toEqual(['a','b']);
  expect(overview.result.rows).toEqual(original.result.rows);expect(overview.result.series).toEqual(original.result.series);
  expect(JSON.stringify(focused.result.extra)).not.toContain('point-b');
 });
 it('keeps an invalid focus and difference selection from discarding the current scope',()=>{
  const original=snapshot();const focused=focusEnergyFlowSnapshot(original,'a');
  expect(focusEnergyFlowSnapshot(focused,'absent')).toBe(focused);
  expect(focusEnergyFlowSnapshot(focused,'__energyFlowDifference__:a')).toBe(focused);
 });
});

describe('energy flow diagnostics',()=>{
 it('derives overview submeter and difference from independent roots rather than the synthetic summary fork',()=>{
  const data=energyFlowData(snapshot().result)!;
  expect(energyFlowStats(data)).toMatchObject({total:180,submeter:160,difference:20,count:2});
  expect(energyFlowStats(energyFlowData(focusEnergyFlowSnapshot(snapshot(),'a1').result)!)).toMatchObject({total:60,submeter:50,difference:10,count:1});
 });
 it('keeps missing diagnostics unknown and negative real differences signed',()=>{
  const data=energyFlowData(snapshot().result)!;
  const missing={...data,nodes:data.nodes.map(n=>n.id==='a'?{...n,submeter:null,balanceQuality:'missing'}:n)};
  expect(energyFlowStats(missing)).toMatchObject({total:180,submeter:null,difference:null});
  const negative={...data,nodes:data.nodes.map(n=>n.id==='a'?{...n,submeter:120,difference:-20,balanceQuality:'negativeBalance'}:n)};
  expect(energyFlowStats(negative).difference).toBe(-20);
 });
 it('does not include unassigned readings or duplicate descendants in overview totals',()=>{
  const data=energyFlowData(snapshot().result)!;
  expect(energyFlowStats({...data,unassigned:[node('very-large',1000000)]}).total).toBe(180);
 });
});

describe('energy flow graph geometry',()=>{
 it('shows three levels and preserves the source values and proportional flow widths',()=>{
  const data=energyFlowData(snapshot().result)!;const before=structuredClone(data);const layout=energyFlowLayout(data);
  expect(layout.nodes.map(n=>n.node.id)).toEqual([summaryId,'a','a1','a2','__energyFlowDifference__:a','b']);
  expect(layout.nodes.some(n=>n.node.id==='a11')).toBe(false);
  const first=layout.links.find(link=>link.link.target==='a')!,second=layout.links.find(link=>link.link.target==='b')!;
  expect(first.thickness/second.thickness).toBeCloseTo(100/80);expect(first.link.value).toBe(100);expect(data).toEqual(before);
 });
 it('preserves nodes at incomplete or negative forks without creating or rescaling flows',()=>{
  const data=energyFlowData(snapshot().result)!;
  const invalid={...data,nodes:data.nodes.map(n=>n.id==='a'?{...n,balanceQuality:'negativeBalance',difference:-20}:n),links:data.links.filter(link=>link.source!=='a')};
  const graph=energyFlowLayout(invalid);
  expect(graph.nodes.some(n=>n.node.id==='a1')).toBe(true);expect(graph.links.filter(link=>link.link.source==='a')).toEqual([]);
 });
 it('keeps zero and missing readings as label-only nodes and never invents zero-width links',()=>{
  const data=energyFlowData(snapshot().result)!;
  const special={...data,nodes:[...data.nodes,node('zero',0,'a'),node('missing',null,'a')],links:[...data.links,{source:'a',target:'zero',value:0,quality:'ok',sourceIds:[],percentage:null}]};
  const graph=energyFlowLayout(special);
  expect(graph.nodes.find(n=>n.node.id==='zero')?.height).toBe(0);expect(graph.nodes.find(n=>n.node.id==='missing')?.height).toBe(0);
  expect(graph.links.some(n=>n.link.target==='zero')).toBe(false);
 });
 it('terminates malformed cyclic parent graphs while retaining each node once',()=>{
  const original=snapshot();const data=energyFlowData(original.result)!;data.nodes.find(n=>n.id==='a')!.parentId='a11';
  const focused=focusEnergyFlowSnapshot(original,'a');
  expect(new Set(energyFlowData(focused.result)!.nodes.map(n=>n.id)).size).toBe(6);
  expect(energyFlowBreadcrumbs(focused).length).toBeLessThanOrEqual(data.nodes.length);
 });
});

describe('energy flow rendered details',()=>{
 it('identifies a virtual sum as a consistency check without implying an independent loss test',()=>{
  const original=snapshot();const data=energyFlowData(original.result)!;
  Object.assign(data.nodes.find(node=>node.id==='a')!,{balanceMode:'consistency',lossEligible:false});
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:original,onFocus:()=>{},exporting:false}));
  expect(html).toContain('计算一致性检查');
  expect(html).toContain('虚拟合计与其来源的差额不能用于证明没有泄漏。');
 });
 it('explains an unknown historic topology without presenting current relationships as historical fact',()=>{
  const original=snapshot();const data=energyFlowData(original.result)!;
  data.nodes=data.nodes.map(node=>({...node,balanceQuality:'topologyUnknown'}));data.links=[];
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:original,onFocus:()=>{},exporting:false}));
  expect(html).toContain('历史计量关系尚未确认');
 });
 it('renders the approved graph, keyboard nodes, sources and a separate unassigned table',()=>{
  const original=snapshot();original.display={objects:{electric:'电能'},sources:{'point-a':'能源汇总源点'},meterKinds:{}};
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:original,onFocus:()=>{},exporting:false}));
  expect(html).toContain('data-flow-value="100"');expect(html).toContain('role="button" tabindex="0"');
  expect(html).toContain('能源汇总源点');expect(html).toContain('未归属表计');expect(html).toContain('上级对象');
 });
 it('renders real parent names and original point IDs after focusing a nested meter',()=>{
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:focusEnergyFlowSnapshot(snapshot(),'a1'),onFocus:()=>{},exporting:false}));
  expect(html).toContain('point-a11');expect(html).not.toContain('point-b');expect(html).not.toContain('energy-flow-unassigned');
  expect(html).toContain('<td>能源汇总</td>');expect(html).toContain('aria-current="page">a1');
 });
 it('keeps negative discrepancies explicit and does not turn a zero reading into a percentage',()=>{
  const original=snapshot();const data=energyFlowData(original.result)!;
  data.nodes=data.nodes.map(n=>n.id==='a'?{...n,balanceQuality:'negativeBalance',difference:-20}:n);
  data.nodes.push(node('zero',0,'a',{percentage:0}));data.links=data.links.filter(link=>link.source!=='a');
  const html=renderToStaticMarkup(createElement(EnergyFlowView,{snapshot:original,onFocus:()=>{},exporting:false}));
  expect(html).toContain('差额为 -20 kWh');expect(html).not.toContain('data-flow-source="a"');
  expect(html.match(/data-flow-row="zero"[\s\S]*?<\/tr>/)?.[0]).not.toContain('0%');
 });
 it('localizes system labels in English while preserving real Chinese meter names',async()=>{
  vi.resetModules();vi.stubGlobal('navigator',{language:'en-US'});
  try{const {EnergyFlowView:EnglishView}=await import('./EnergyFlowView');
   const html=renderToStaticMarkup(createElement(EnglishView,{snapshot:snapshot(),onFocus:()=>{},exporting:false}));
   expect(html).toContain('Utility summary');expect(html).toContain('Metering difference');expect(html).toContain('>能源汇总');expect(html).not.toContain('返回概览');
  }finally{vi.stubGlobal('navigator',{language:'zh-CN'});vi.resetModules();}
 });
});
