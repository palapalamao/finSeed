import {afterEach,beforeAll,describe,expect,it,vi} from 'vitest';
import type {ReportSnapshot} from './types';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});
beforeAll(async()=>{await import('./ReportView');},30000);

function snapshot(overlap=true):ReportSnapshot{
 const from='2026-10-19T00:00:00+08:00',to='2026-10-26T00:00:00+08:00';
 return {title:'Share report',project:'cubeTest',generatedAt:from,request:{kind:'proportion',dimension:'space',nodeIds:['a','b'],from,to,period:'day',metric:'energy',perArea:false},result:{kind:'proportion',from,to,period:'day',warnings:[],summary:{},series:[{id:'a',nodeId:'a',name:'Business name A',unit:'kWh',points:[{ts:from,value:30,quality:'filtered',sourceIds:['pa']}]},{id:'b',nodeId:'b',name:'Business name B',unit:'kWh',points:[{ts:from,value:10,quality:'filtered',sourceIds:['pb']}]}],rows:[{nodeId:'a',name:'Business name A',value:30,percentage:overlap?null:75,percentageBasis:overlap?'overlappingScopes':'knownUsage'},{nodeId:'b',name:'Business name B',value:10,percentage:overlap?null:25,percentageBasis:overlap?'overlappingScopes':'knownUsage'}]}};
}

async function render(source:ReportSnapshot,language='zh-CN'){
 vi.resetModules();vi.stubGlobal('navigator',{language,languages:[language]});
 const [{createElement},{renderToStaticMarkup},{ReportView}]=await Promise.all([import('react'),import('react-dom/server'),import('./ReportView')]);
 return renderToStaticMarkup(createElement(ReportView,{snapshot:source}));
}

describe('share chart selection guidance',()=>{
 it.each(['zh-CN','en-US'])('replaces an overlapping pie with actionable %s guidance and retains the report amounts',async language=>{
  const source=snapshot(),before=structuredClone(source),html=await render(source,language);
  expect(html).toContain(language==='zh-CN'?'计量范围重叠，相关对象无法计算占比':'The selected scopes overlap; shares cannot be calculated for the affected objects');
  expect(html).toContain(language==='zh-CN'?'取消总表':'deselect the parent meter');
  expect(html).toContain(language==='zh-CN'?'父组和子组':'a parent group and its descendants');
  expect(html).not.toContain('class="report-chart"');
  expect(html).toContain('Business name A');expect(html).toContain('Business name B');expect(source).toEqual(before);
 });
 it('keeps the pie and server percentages for nonoverlapping objects',async()=>{
  const source=snapshot(false),before=structuredClone(source),html=await render(source);
  expect(html).toContain('class="report-chart"');expect(html).not.toContain('计量范围重叠，相关对象无法计算占比');expect(source).toEqual(before);
 });
 it('does not label missing consumption as overlapping selections',async()=>{
  const source=snapshot();source.result.rows.forEach(row=>row.percentageBasis='noKnownUsage');
  expect(await render(source)).not.toContain('计量范围重叠，相关对象无法计算占比');
 });
 it('leaves other chart types unchanged',async()=>{
  const source=snapshot();source.result.kind=source.request.kind='ranking';
  const html=await render(source);expect(html).toContain('class="report-chart"');expect(html).not.toContain('计量范围重叠，相关对象无法计算占比');
 });
 it('retains valid energy-category pies when another category overlaps',async()=>{
  const source=snapshot();source.result.rows.push({name:'Water meter',categoryId:'water',unit:'m³',value:5,percentage:100,percentageBasis:'knownUsage'});
  const before=structuredClone(source),html=await render(source);
  expect(html).toContain('class="report-chart"');expect(html).toContain('取消总表');expect(source).toEqual(before);
 });
});
