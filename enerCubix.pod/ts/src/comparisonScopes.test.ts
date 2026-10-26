import {afterEach,describe,expect,it,vi} from 'vitest';
import {EnerCubixApi} from './api';
import type {ReportSnapshot} from './types';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));

afterEach(()=>{vi.restoreAllMocks();vi.unstubAllGlobals();vi.resetModules();});
describe('readonly comparison scope API',()=>{
 it('passes encoded meter IDs and cancellation through the authenticated GET request',async()=>{
  const api=new EnerCubixApi('cubeTest'),signal=new AbortController().signal;
  const request=vi.spyOn(api,'request').mockResolvedValue({scopes:[]});
  expect(await api.comparisonScopes(['native:master','native:other/2'],signal)).toEqual({scopes:[]});
  expect(request).toHaveBeenCalledWith('comparison-scopes?nodeIds=native%3Amaster%2Cnative%3Aother%2F2',undefined,signal);
 });
});
describe('comparison scope reasons',()=>{
 it.each(['zh-CN','en-US'])('presents the frozen physical union without summing master groups in %s',async language=>{
  vi.resetModules();vi.stubGlobal('navigator',{language});
  const {readableReportValue}=await import('./reportDisplay');
  const source:ReportSnapshot={title:'Balance',project:'test',generatedAt:'2026-10-26',request:{kind:'leak',nodeIds:['master'],from:'2026-10-01',to:'2026-10-02',period:'day',metric:'energy',perArea:false},result:{kind:'leak',from:'2026-10-01',to:'2026-10-02',period:'day',series:[],rows:[],warnings:[],summary:{},extra:{comparisonUnion:[{categoryId:'electric',unit:'kWh',meterIds:['a'],sourceIds:['p'],value:17.25,knownValue:17.25,quality:'ok',knownQuality:'ok',scopeQuality:'ok',basis:'physicalBoundary',completeSelection:false}]}},display:{objects:{electric:'Electric',a:'Frozen branch A'},sources:{p:'Frozen source'},meterKinds:{}}};
  const before=structuredClone(source),text=JSON.stringify(readableReportValue(source,'',source.result.extra));
  expect(text).toContain(language==='zh-CN'?'物理分表并集合计（已去重）':'Physical submeter union total (deduplicated)');expect(text).toContain(language==='zh-CN'?'完整边界选择':'Complete boundary selection');expect(text).toContain(language==='zh-CN'?'物理计量边界':'Physical metering boundary');
  expect(text).toContain('Frozen branch A');expect(text).toContain('Frozen source');expect(text).toContain('17.25');expect(text).not.toContain('completeSelection');expect(source).toEqual(before);
 });
 it.each(['zh-CN','en-US'])('localizes boundary quality and generic validation errors in %s',async language=>{
  vi.resetModules();vi.stubGlobal('navigator',{language});
  const[{serverMessage},{qualityLabel}]=await Promise.all([import('./i18n'),import('./reportQuality')]);
  for(const code of ['comparisonEmpty','comparisonPartial','comparisonUnavailable','comparisonUnresolved','comparisonNonAdditive','comparisonMissingSource','comparisonCycle','comparisonIncompatible'])expect(qualityLabel(code)).not.toContain(code);
  for(const code of ['comparisonInvalidBasis','comparisonMasterRequired','comparisonInvalidMembers'])expect(serverMessage(code)).not.toContain(code);
  expect(qualityLabel('comparisonPartial')).toContain(language==='zh-CN'?'差额不用于判定泄漏':'cannot establish leakage');
 });
});
