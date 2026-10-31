import {describe,it,expect} from 'vitest';
import {decodeCockpitPayload} from './cockpitPayload';

const id='a'.repeat(64),other='b'.repeat(64);
const wire=(snapshot:unknown,evidence:Record<string,unknown>={})=>({payloadEncoding:'compact-v1',codecVersion:1,snapshot,evidence});
describe('negotiated cockpit compact-v1',()=>{
 it('preserves values, absolute DST boundaries, source quality and shared identity',()=>{
  const evidence={$cockpitTable:{columns:['from','to','value','quality','pointId'],rows:[['2026-11-01T01:00:00-04:00','2026-11-01T01:00:00-05:00',0,'ok','p'],['2026-11-01T01:00:00-05:00','2026-11-01T02:00:00-05:00',null,'na','p'],['2026-11-01T02:00:00-05:00','2026-11-01T03:00:00-05:00',-2.5,'missing','p']]}};
  const result=decodeCockpitPayload<{rows:unknown;overview:unknown}>(wire({rows:{$cockpitRef:id},overview:{$cockpitRef:id}},{[id]:evidence}));
  expect(result.rows).toEqual(evidence.$cockpitTable.rows.map(([from,to,value,quality,pointId])=>({from,to,value,quality,pointId})));
  expect(result.rows).toBe(result.overview);
 });
 it('keeps legacy snapshots unchanged and does not pollute object prototypes',()=>{
  const legacy={schemaVersion:1};expect(decodeCockpitPayload(legacy)).toBe(legacy);
  const result=decodeCockpitPayload<Record<string,unknown>[]>(wire({$cockpitTable:{columns:['__proto__'],rows:[[{polluted:true}]]}}));
  expect(Object.hasOwn(result[0],'__proto__')).toBe(true);expect(({} as {polluted?:boolean}).polluted).toBeUndefined();
 });
 it('rejects unknown versions, dangling/cyclic refs, malformed tables and depth bombs',()=>{
  for(const bad of [{...wire({}),codecVersion:2},{...wire({}),payloadEncoding:'other'},wire({$cockpitRef:id}),wire({$cockpitRef:id},{[id]:{$cockpitRef:other},[other]:{$cockpitRef:id}}),wire({$cockpitTable:{columns:['a','a'],rows:[[0,1]]}}),wire({$cockpitTable:{columns:['a'],rows:[[0,1]]}})])expect(()=>decodeCockpitPayload(bad)).toThrow('invalid_response');
  let deep:unknown=0;for(let i=0;i<82;i++)deep={child:deep};expect(()=>decodeCockpitPayload(wire(deep))).toThrow('invalid_response');
 });
 it('bounds references, tables, columns and total decoded rows',()=>{
  const refs=Array.from({length:10001},()=>({$cockpitRef:id}));expect(()=>decodeCockpitPayload(wire({refs},{[id]:0}))).toThrow('invalid_response');
  const tables=Array.from({length:513},()=>({$cockpitTable:{columns:[],rows:[]}}));expect(()=>decodeCockpitPayload(wire({tables}))).toThrow('invalid_response');
  expect(()=>decodeCockpitPayload(wire({$cockpitTable:{columns:Array.from({length:65},(_,i)=>String(i)),rows:[]}}))).toThrow('invalid_response');
  expect(()=>decodeCockpitPayload(wire({$cockpitTable:{columns:[],rows:Array(500001).fill([])}}))).toThrow('invalid_response');
 });
 it('restores escaped business objects containing reserved control keys literally',()=>{
  const business={$cockpitRef:'business-data',$cockpitTable:{columns:['business'],rows:[[0]]},$cockpitLiteral:{nested:true}};
  expect(decodeCockpitPayload(wire({parameters:{$cockpitLiteral:business}}))).toEqual({parameters:business});
 });
});
