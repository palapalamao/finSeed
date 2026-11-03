import {expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import budgetRaw from '../tests/fixtures/cockpit-budget-rules.json';
import spaceRaw from '../tests/fixtures/cockpit-space-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import type {Catalog} from './types';
import {CockpitBudget} from './CockpitBudget';
import {CockpitSpace} from './CockpitSpace';
import {freezeCockpitExport,cockpitWorkbook} from './cockpitExports';
import {initializeLocale,translateFor,type Locale} from './i18n';
import {cockpitDefaultSpaceFocus,cockpitSpaceUsage} from './cockpitSpaceProjection';

it('chooses only readable snapshot sites, preserves valid focus and never infers an unloaded ancestor',()=>{
 const snapshot=structuredClone(spaceRaw) as unknown as CockpitSnapshot,catalog={records:[],spaceSource:'fin'} as unknown as Catalog,before=structuredClone(snapshot);
 expect(cockpitDefaultSpaceFocus(snapshot,catalog)).toBe('s');expect(cockpitDefaultSpaceFocus(snapshot,catalog,'f')).toBe('f');expect(snapshot).toEqual(before);
 const other={...snapshot.modules.space!.data!.nodes.find(node=>node.id==='s')!,id:'aaa',nativeId:'aaa'};snapshot.modules.space!.data!.nodes.unshift(other);
 expect(cockpitDefaultSpaceFocus(snapshot,catalog)).toBe('s');snapshot.context.reportScope.nodeIds=['aaa'];expect(cockpitDefaultSpaceFocus(snapshot,catalog)).toBe('aaa');snapshot.context.reportScope.nodeIds=['s'];snapshot.modules.space!.data!.nodes.shift();
 const nodes=snapshot.modules.space!.data!.nodes,site=nodes.find(node=>node.id==='s')!;
 Object.assign(site,{value:null,knownValue:null,completeValue:null,valueBasis:'unavailable',quality:'notLoaded',reasonCodes:['FOCUS_NOT_LOADED']});snapshot.context.reportScope.nodeIds=['f'];
 expect(cockpitDefaultSpaceFocus(snapshot,catalog)).toBe('f');expect(cockpitSpaceUsage(site).value).toBeNull();
 snapshot.modules.space!.data!.nodes=nodes.filter(node=>node.nodeKind!=='site');expect(cockpitDefaultSpaceFocus(snapshot,catalog,'gone')).toBe('f');
 snapshot.modules.space!.data!.nodes=[];expect(cockpitDefaultSpaceFocus(snapshot,catalog)).toBeUndefined();
});

for(const language of ['zh-CN','en-US'] as Locale[]){
 it('shows independent reference rates and exports frozen numeric evidence '+language,async()=>{
  initializeLocale(language,'reference-test');const snapshot=structuredClone(budgetRaw.snapshot) as unknown as CockpitSnapshot,b=snapshot.modules.kpis!.data!.budget!;
  Object.assign(b,{status:'unavailable',comparisonStatus:'unavailable',budgetStatus:'ok',variancePct:null,monthUsagePct:null,periodActualCost:1101690.70961312,periodBudget:1019918.9814814816,monthBudget:11000000,costQuality:'estimated',costValueBasis:'knownSubtotal',referenceVariancePct:8.017472918570551,referenceMonthUsagePct:10.015370087392,referenceBasis:{quality:'estimated',valueBasis:'knownSubtotal',reasonCodes:['estimated'],from:snapshot.context.time.from,effectiveTo:snapshot.context.asOf,asOf:snapshot.context.asOf}});
  const html=renderToStaticMarkup(<CockpitBudget snapshot={snapshot}/>);
  expect(html).toContain(translateFor(language,'参考偏差'));expect(html).toContain('8.02');expect(html).toContain(translateFor(language,'已统计费用占月预算'));expect(html).toContain('10.02');expect(html).toContain(translateFor(language,'已有费用含不完整或估算数据；比例仅供参考，不作达标判断。'));
  const packet=freezeCockpitExport(snapshot,language,{});Object.assign(b,{referenceVariancePct:999});
  const book=await cockpitWorkbook(packet),sheet=book.getWorksheet(translateFor(language,'预算经营参照'))!,rows=sheet.getSheetValues() as unknown[][];
  expect(rows.find(row=>row?.[1]===translateFor(language,'参考偏差'))?.[2]).toBe(8.017472918570551);
  expect(rows.find(row=>row?.[1]===translateFor(language,'已统计费用占月预算'))?.[2]).toBe(10.015370087392);
  expect(packet.snapshot.modules.kpis!.data!.budget!.variancePct).toBeNull();
  Object.assign(b,{referenceVariancePct:null,referenceMonthUsagePct:0,periodBudget:0,periodActualCost:0});
  const zero=renderToStaticMarkup(<CockpitBudget snapshot={snapshot}/>);expect(zero).toContain('>0%</strong>');expect(zero).not.toContain('NaN');
 },20000);
 it('shows same-snapshot subtotal and cutoff without inventing complete consumption '+language,()=>{
  initializeLocale(language,'reference-test');const snapshot=structuredClone(spaceRaw) as unknown as CockpitSnapshot,site=snapshot.modules.space!.data!.nodes.find(node=>node.nodeKind==='site')!;
  const catalog={project:'test',spaceSource:'fin',records:[],user:{name:'test',canWrite:false}} as unknown as Catalog;
  const render=()=>renderToStaticMarkup(<CockpitSpace snapshot={snapshot} catalog={catalog} focusObjectId={site.id} onFocus={()=>{}} onPromote={()=>{}} onProfile={()=>{}} onFlow={()=>{}}/>);
  Object.assign(site,{value:30,knownValue:30,completeValue:null,valueBasis:'knownSubtotal',quality:'partial'});
  expect(render()).toContain('<dt>'+translateFor(language,'已有用量小计')+'</dt><dd>30');expect(render()).toContain(snapshot.context.asOf);
  site.value=null;expect(render()).toContain('<dd>30 kWh');
  Object.assign(site,{value:0,knownValue:0});expect(render()).toContain('<dd>0 kWh');
  Object.assign(site,{value:null,knownValue:null,valueType:'na'});expect(render()).toContain('<dd>NA kWh');
  Object.assign(site,{value:null,knownValue:null,valueType:'null',valueBasis:'unavailable',quality:'notLoaded'});expect(render()).toContain('<dd>— kWh');
 });
}
