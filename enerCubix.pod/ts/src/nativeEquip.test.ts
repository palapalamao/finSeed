import {describe,it,expect} from 'vitest';
import {enrollmentRecord,primaryCandidates,mainEnergySources} from './nativeEquip';
import type {EnerCubixRecord} from './types';
describe('native equipment energy identity',()=>{
 const eq={id:'e',mod:'v1',kind:'space' as const,name:'设备',nativeSourceKind:'equip'};
 const points=[{id:'p',name:'电量',his:true,equipId:'e',unit:'Wh'},{id:'other',name:'其他设备点',his:true,equipId:'x',unit:'kWh'},{id:'disabled',name:'无历史',his:false,equipId:'e',unit:'kWh'},{id:'water',name:'水量',his:true,equipId:'e',unit:'m³'}];
 it('requires own historized point and supports compatible units',()=>{expect(primaryCandidates(points,'e','kWh').map(row=>row.id)).toEqual(['p']);expect(()=>enrollmentRecord(eq,points[1],'cat')).toThrow();expect(()=>enrollmentRecord(eq,points[2],'cat')).toThrow();});
 it('uses equipment identity and point source without native structural edits',()=>{const rec=enrollmentRecord(eq,points[0],'cat');expect(rec.id).toBe('e');expect(rec.mod).toBe('v1');expect(rec.pointId).toBe('p');expect(rec).not.toHaveProperty('parentId');expect(rec).not.toHaveProperty('siteRef');});
 it('marks only saved physical energy bindings, excluding sensors, formulas and compatibility aliases',()=>{
  const records:EnerCubixRecord[]=[{id:'e',kind:'meter',name:'电表',pointId:'main'},{id:'total',kind:'totalMeter',name:'总表',pointId:'total-point'},{id:'sensor',kind:'sensor',name:'参考量',pointId:'sensor-point'},{id:'formula',kind:'meter',name:'公式',pointId:'formula-point',expressionId:'formula-id'},{id:'alias',kind:'meter',name:'旧别名',pointId:'main',canonicalId:'e'},{id:'unbound',kind:'meter',name:'未绑定'}];
  const sources=mainEnergySources(records);
  expect([...sources.keys()]).toEqual(['main','total-point']);expect(sources.get('main')?.id).toBe('e');
 });
});
