import {describe,it,expect,vi,beforeEach} from 'vitest';
const {transport}=vi.hoisted(()=>({transport:vi.fn()}));
vi.mock('haystack-nclient',()=>({finCsrfFetch:transport}));
import {FinEnergyApi} from './api';

describe('catalog in-flight reads',()=>{
 beforeEach(()=>transport.mockReset());
 it('coalesces only concurrent equivalent reads, never a later refresh or another API owner',async()=>{
  let release!:(response:Response)=>void;
  transport.mockImplementationOnce(()=>new Promise<Response>(resolve=>{release=resolve;}));
  const api=new FinEnergyApi('project'),a=api.catalog('analysis'),b=api.catalog('analysis');
  expect(a).toBe(b);expect(transport).toHaveBeenCalledTimes(1);
  release(new Response(JSON.stringify({ok:true,data:{catalogMode:'analysis',project:'project',records:[]}})));await a;
  transport.mockImplementation(async()=>new Response(JSON.stringify({ok:true,data:{records:[]}})));
  await api.catalog('analysis');await api.catalog('full');await new FinEnergyApi('other').catalog('analysis');
  expect(transport).toHaveBeenCalledTimes(4);
  expect(transport.mock.calls[0][0]).toContain('catalog?mode=analysis');expect(transport.mock.calls[2][0]).toMatch(/\/catalog$/);
 });
 it('clears rejected in-flight reads so explicit retry can succeed',async()=>{
  transport.mockRejectedValueOnce(new Error('network'));
  const api=new FinEnergyApi('project');await expect(api.catalog('analysis')).rejects.toThrow();
  transport.mockResolvedValueOnce(new Response(JSON.stringify({ok:true,data:{records:[]}})));
  await expect(api.catalog('analysis')).resolves.toEqual({records:[]});expect(transport).toHaveBeenCalledTimes(2);
 });
});
