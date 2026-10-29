import {afterEach,beforeAll,describe,expect,it,vi} from 'vitest';
import {utilityScopeAllowed} from './dimensionTree';
import type {ReportSnapshot} from './types';

// Prepare the large UI dependency graph outside the individual rendering checks.
beforeAll(async()=>{await import('./ReportView');},120000);

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});
function source(basis='knownUsage'):ReportSnapshot{
 const from='2026-10-01T00:00:00+08:00',to='2026-10-02T00:00:00+08:00';
 return {title:'End uses',project:'cubeTest',generatedAt:from,request:{kind:'utility',dimension:'metering',nodeIds:['a','b','c'],from,to,period:'day',metric:'energy',perArea:false},result:{kind:'utility',from,to,period:'day',warnings:[],summary:{},rows:[],series:[],extra:{utilityShares:[{id:'e|lighting',name:'Lighting',utilityId:'lighting',categoryId:'e',unit:'kWh',value:300,percentage:basis==='knownUsage'?50:null,percentageBasis:basis,meterIds:['a','b']},{id:'e|power',name:'Power',utilityId:'power',categoryId:'e',unit:'kWh',value:300,percentage:basis==='knownUsage'?50:null,percentageBasis:basis,meterIds:['c']}],utilityMembers:[{nodeId:'a',name:'Light A',utilityId:'lighting',utilityName:'Lighting',categoryId:'e',unit:'kWh',value:100,quality:'ok',coverage:1},{nodeId:'b',name:'Light B',utilityId:'lighting',utilityName:'Lighting',categoryId:'e',unit:'kWh',value:200,quality:'ok',coverage:1},{nodeId:'c',name:'Power C',utilityId:'power',utilityName:'Power',categoryId:'e',unit:'kWh',value:300,quality:'ok',coverage:1}]}}};
}
async function render(s:ReportSnapshot,language:string){
 vi.resetModules();(await import('./i18n')).initializeLocale(language);
 const [{createElement},{renderToStaticMarkup},{ReportView}]=await Promise.all([import('react'),import('react-dom/server'),import('./ReportView')]);
 return renderToStaticMarkup(createElement(ReportView,{snapshot:s}));
}
describe('end-use presentation',()=>{
 it.each(['zh-CN','en-US'])('presents one shared end-use pie and own-meter details in %s',async language=>{
  const s=source(),before=structuredClone(s),html=await render(s,language);
  expect(html).toContain(language==='zh-CN'?'所选表计的分项构成':'End uses of selected meters');
  expect((html.match(/class="utility-chart"/g)||[])).toHaveLength(1);
  expect(html).toContain('Light A');expect(html).toContain('Power C');expect(html).toContain('Lighting');expect(html).toContain('600');
  expect(s).toEqual(before);
 });
 it.each(['zh-CN','en-US'])('keeps own amounts but suppresses an overlapping pie in %s',async language=>{
  const html=await render(source('overlappingScopes'),language);
  expect(html).toContain(language==='zh-CN'?'计量范围重叠':'selected scopes overlap');
  expect(html).not.toContain('class="utility-chart"');expect(html).toContain('Light A');expect(html).toContain('Power C');
 });
 it('permits own-meter and nested scope selection in every current view',()=>{
  const rs=[{id:'s',kind:'space' as const,name:'Site'},{id:'f',kind:'space' as const,name:'Floor',parentId:'s'},{id:'room',kind:'space' as const,name:'Room',parentId:'f'},{id:'m',kind:'meter' as const,name:'Light',utilityId:'u',spaceId:'room'}];
  expect(utilityScopeAllowed(rs,'m','space')).toBe(true);expect(utilityScopeAllowed(rs,'m','organization')).toBe(true);expect(utilityScopeAllowed(rs,'room','space')).toBe(true);
 });
});
