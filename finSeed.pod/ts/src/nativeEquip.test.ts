import {describe,it,expect} from 'vitest';
import {enrollmentRecord,primaryCandidates} from './nativeEquip';
describe('native equipment energy identity',()=>{
 const eq={id:'e',mod:'v1',kind:'space' as const,name:'设备',nativeSourceKind:'equip'};
 const points=[{id:'p',name:'电量',his:true,equipId:'e',unit:'Wh'},{id:'other',name:'其他设备点',his:true,equipId:'x',unit:'kWh'},{id:'disabled',name:'无历史',his:false,equipId:'e',unit:'kWh'},{id:'water',name:'水量',his:true,equipId:'e',unit:'m³'}];
 it('requires own historized point and supports compatible units',()=>{expect(primaryCandidates(points,'e','kWh').map(row=>row.id)).toEqual(['p']);expect(()=>enrollmentRecord(eq,points[1],'cat')).toThrow();expect(()=>enrollmentRecord(eq,points[2],'cat')).toThrow();});
 it('uses equipment identity and point source without native structural edits',()=>{const rec=enrollmentRecord(eq,points[0],'cat');expect(rec.id).toBe('e');expect(rec.mod).toBe('v1');expect(rec.pointId).toBe('p');expect(rec).not.toHaveProperty('parentId');expect(rec).not.toHaveProperty('siteRef');});
});
