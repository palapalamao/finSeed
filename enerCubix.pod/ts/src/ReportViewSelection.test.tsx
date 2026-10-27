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
 it.each(['zh-CN','en-US'])('shows restored historical membership and still refuses an unsupported leakage claim in %s',async language=>{
  const source=snapshot();source.title='Recovered balance';source.request.kind=source.result.kind='leak';source.request.nodeIds=['a'];source.result.series=source.result.series.slice(0,1);source.result.series[0].categoryId='e';source.result.rows=[{nodeId:'a',categoryId:'e',ts:source.request.from,knownTotal:232908,knownSubmeter:258153,difference:null,percentage:null,membershipQuality:'snapshotRecovered'}];source.result.extra={leakTotals:[{nodeId:'a',categoryId:'e',unit:'kWh',knownTotal:232908,knownSubmeter:258153,difference:null,percentage:null,membershipQuality:'snapshotRecovered',balanceMode:'unknown'}],leakBranches:[]};
  const before=structuredClone(source),html=await render(source,language);
  expect(html).toContain(language==='zh-CN'?'部分旧关系已按备份恢复':'Some historical relationships were restored from backups');expect(html).toContain('258153');expect(html).toContain(language==='zh-CN'?'差额不用于泄漏判断':'does not establish leakage');expect(html).not.toContain('ant-alert-error');expect(source).toEqual(before);
 });
 it.each(['zh-CN','en-US'])('shows own leakage-report consumption separately from an unreliable balance in %s',async language=>{
  const source=snapshot();source.title='Balance';source.request.kind=source.result.kind='leak';source.request.nodeIds=['a'];source.result.series=source.result.series.slice(0,1);source.result.series[0].categoryId='e';source.result.rows=[{nodeId:'a',categoryId:'e',ts:source.request.from,total:null,submeter:null,difference:null,knownTotal:100,knownSubmeter:40}];source.result.extra={leakTotals:[{nodeId:'a',categoryId:'e',unit:'kWh',knownTotal:100,knownSubmeter:40,difference:null,percentage:null,balanceMode:'consistency',membershipQuality:'topologyUnknown'}],leakBranches:[],leakOwnUsage:[{masterId:'a',nodeId:'a',categoryId:'e',name:'Business name A',value:100,unit:'kWh',quality:'filtered'},{masterId:'a',nodeId:'b',categoryId:'e',name:'Business name B',value:80,unit:'kWh',quality:'filtered'}]};
  const before=structuredClone(source),html=await render(source,language);
  expect(html).toContain(language==='zh-CN'?'各表自身已有用量':'Each meter’s own available consumption');expect(html).toContain(language==='zh-CN'?'不代表完整区间的计量差额或实际泄漏':'does not establish a complete-period balance or actual leakage');expect(html).toContain(language==='zh-CN'?'计算一致性':'consistency check');expect(html).toContain('Business name B');expect(html).toContain('ant-alert-warning');expect(html).not.toContain('ant-alert-error');expect(source).toEqual(before);
 });
 it.each(['zh-CN','en-US'])('replaces an overlapping pie with actionable %s guidance and retains the report amounts',async language=>{
  const source=snapshot(),before=structuredClone(source),html=await render(source,language);
  expect(html).toContain(language==='zh-CN'?'计量范围重叠，相关对象无法计算占比':'The selected scopes overlap; shares cannot be calculated for the affected objects');
  expect(html).toContain(language==='zh-CN'?'取消总表':'deselect the parent meter');
  expect(html).toContain(language==='zh-CN'?'父组和子组':'a parent group and its descendants');
  expect(html).not.toContain('class="report-chart"');
  expect(html).toContain('ant-alert-error');
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
