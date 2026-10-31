import {afterEach,describe,expect,it,vi} from 'vitest';
import type {EnerCubixRecord,ReportSnapshot} from './types';
afterEach(()=>vi.resetModules());

describe('explicit statistical area',()=>{
 it.each(['zh-CN','en-US'])('exports original native area references, revisions and units in %s',async language=>{
  (await import('./i18n')).initializeLocale(language);const {areaBasisRows}=await import('./serviceArea');
  const snapshot={result:{extra:{areaBasis:[{nodeId:'__selection__',baseValue:300,baseUnit:'kWh',value:0.3,unit:'kWh/m²',area:{value:1000,quality:'ok',unit:'m²',sources:[{id:'floor',nativeRef:'native-floor',mod:'floor-v1',name:'Frozen 1F',area:1000,source:'space',nativeArea:{nativeRef:'native-floor',mod:'floor-v1',tag:'area',value:10763.91,unit:'ft²',areaM2:1000}}]}}]}}} as unknown as ReportSnapshot;
  const before=structuredClone(snapshot),text=areaBasisRows(snapshot).join('');expect(text).toContain('native-floor');expect(text).toContain('floor-v1');expect(text).toContain('10,763.91 ft²');expect(text).toContain('300 kWh ÷ 1,000 m² = 0.3 kWh/m²');expect(snapshot).toEqual(before);
 });
 it('offers only native sites and floors and submits an area-only patch',async()=>{
  const {areaSpaces,spaceAreaPayload}=await import('./serviceArea');
  const site:EnerCubixRecord={id:'overlay',kind:'space',name:'Campus',mod:'original',nativeReadonly:true,nativeSourceKind:'site',nativeSourceId:'native-site',area:800};
  const records=[site,{id:'floor',kind:'space',name:'1F',parentId:'overlay',nativeReadonly:true,nativeSourceKind:'floor'},{id:'equip',kind:'space',name:'Cabinet',nativeReadonly:true,nativeSourceKind:'equip'},{id:'old',kind:'space',name:'Legacy'}] as EnerCubixRecord[];
  expect(areaSpaces(records).map(row=>row.id)).toEqual(['overlay','floor']);
  expect(spaceAreaPayload(site,1000)).toEqual({id:'overlay',mod:'original',kind:'space',areaOnly:true,area:1000});
  expect(spaceAreaPayload(site,null)).not.toHaveProperty('name');
 });
 it.each(['zh-CN','en-US'])('shows and exports the frozen numerator, denominator and named sources in %s',async language=>{
  (await import('./i18n')).initializeLocale(language);
  const {areaBasisRows}=await import('./serviceArea');
  const snapshot={request:{perArea:true},display:{objects:{m:'Changed live name'}},result:{extra:{areaBasis:[{nodeId:'m',name:'Frozen lighting',baseValue:300,baseUnit:'kWh',value:0.3,unit:'kWh/m²',area:{value:1000,unit:'m²',quality:'ok',sources:[{id:'floor',name:'Frozen 1F',area:1000,source:'space'}]}}]}}} as unknown as ReportSnapshot;
  const before=structuredClone(snapshot),rows=areaBasisRows(snapshot);
  expect(rows[0]).toContain('Frozen lighting');expect(rows[0]).toContain('300 kWh ÷ 1,000 m² = 0.3 kWh/m²');expect(rows[0].join('')).toContain('Frozen 1F');expect(rows.join('')).not.toContain('Changed live name');expect(snapshot).toEqual(before);
  snapshot.result.extra!.areaBasis=[{nodeId:'m',name:'Meter',baseValue:300,baseUnit:'kWh',value:null,unit:'kWh/m²',area:{value:null,quality:'ambiguousArea',unit:'m²',sources:[]}}];
  expect(areaBasisRows(snapshot).join('')).toContain('300 kWh');
  expect(areaBasisRows(snapshot).join('')).toContain(language==='zh-CN'?'面积边界不明确':'Area boundaries are ambiguous');
 });
});
