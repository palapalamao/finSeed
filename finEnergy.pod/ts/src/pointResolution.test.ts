import {describe,it,expect,vi} from 'vitest';
import {reportPointNames} from './reportDisplay';
import type {ReportResult,FinPoint} from './types';

const result=(ids:string[])=>({rows:[{sourceIds:ids}],series:[],summary:{}} as unknown as ReportResult);
describe('exact report point batches',()=>{
 it('exhausts source IDs with bounded transport batches and keeps history metadata',async()=>{
  const ids=Array.from({length:825},(_,i)=>'p'+i);let active=0,peak=0;
  const load=vi.fn(async(batch:string[])=>{active++;peak=Math.max(peak,active);await Promise.resolve();active--;return {items:batch.map(id=>({id,name:id,his:true,hisMode:'cov',hisStart:'2026-11-01T00:00:00Z'}))};});
  const points=await reportPointNames(result([...ids,'p0']),[],load);
  expect(points.map(p=>p.id)).toEqual(ids);expect(load).toHaveBeenCalledTimes(5);
  expect(load.mock.calls.every(([batch])=>batch.length<=200)).toBe(true);expect(peak).toBeLessThanOrEqual(2);
  expect(points[0].hisMode).toBe('cov');
 });
 it('does not resurrect missing or unreadable points and stops on cancellation',async()=>{
  const load=vi.fn(async()=>({items:[{id:'visible',name:'Visible',his:true} as FinPoint]}));
  expect((await reportPointNames(result(['visible','hidden']),[],load)).map(p=>p.id)).toEqual(['visible']);
  const abort=new AbortController();abort.abort();
  await expect(reportPointNames(result(['visible']),[],load,abort.signal)).rejects.toMatchObject({name:'AbortError'});
  expect(load).toHaveBeenCalledTimes(1);
 });
});
