import {expect,it,vi} from 'vitest';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));
import {finCsrfFetch} from 'haystack-nclient';
import {FinEnergyApi} from './api';
import type {CockpitRequest} from './cockpitTypes';

it('reads the cockpit with native FIN POST credentials and a cancellable request',async()=>{
 const api=new FinEnergyApi('building one');
 expect(api).toHaveProperty('cockpit',expect.any(Function));
 const controller=new AbortController();
 const request={schemaVersion:1,requestId:'one',reportScope:{dimension:'space',nodeIds:['site'],selectionIntent:'range'},focusCategoryId:'electricity',time:{preset:'thisMonth',period:'day'},modules:['kpis','trend']};
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:true,data:{snapshotId:'snapshot'}}),{headers:{'content-type':'application/json'}}));
 await (api as unknown as {cockpit:(request:unknown,signal:AbortSignal)=>Promise<unknown>}).cockpit(request,controller.signal);
 expect(finCsrfFetch).toHaveBeenLastCalledWith('/api/building%20one/ext/finEnergy/v1/cockpit',expect.objectContaining({method:'POST',credentials:'same-origin',signal:controller.signal,body:JSON.stringify({...request,payloadEncoding:'compact-v1'})}));
});

const query=():CockpitRequest=>({schemaVersion:1,requestId:'wire',reportScope:{dimension:'space',nodeIds:['site'],selectionIntent:'range'},focusCategoryId:'electricity',time:{preset:'custom',period:'hour',from:'2026-10-30T00:00:00Z',to:'2026-10-30T01:00:00Z'},modules:['kpis','trend']});
it('uses one background run for an eligible long cockpit selection and decodes its complete result',async()=>{
 const request={...query(),time:{preset:'thisYear' as const,period:'month' as const}};
 const api=new FinEnergyApi('test',undefined,true);
 const reply=(data:unknown)=>new Response(JSON.stringify({ok:true,data}));
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(reply({id:'run',state:'running'})).mockResolvedValueOnce(reply({
  id:'run',state:'ready',result:{payloadEncoding:'compact-v1',codecVersion:1,evidence:{},snapshot:{snapshotId:'complete'}},
 }));
 expect(await api.cockpit(request)).toEqual({snapshotId:'complete'});
 expect(finCsrfFetch).toHaveBeenCalledWith('/api/test/ext/finEnergy/v1/query/run',expect.objectContaining({body:JSON.stringify({kind:'cockpit',request:{...request,payloadEncoding:'compact-v1'}})}));
 expect(finCsrfFetch).toHaveBeenLastCalledWith('/api/test/ext/finEnergy/v1/query/status?id=run',expect.objectContaining({method:'GET'}));
});
it('uses the compatible endpoint when the server confirms that background work is unavailable',async()=>{
 const request={...query(),time:{preset:'thisYear' as const,period:'month' as const}};
 const api=new FinEnergyApi('test',undefined,true);
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:false,error:{code:'QUERY_RUN_UNAVAILABLE',msg:'queryRunUnavailable'}}),{status:409}));
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:true,data:{snapshotId:'sync'}})));
 expect(await api.cockpit(request)).toEqual({snapshotId:'sync'});
 expect(finCsrfFetch).toHaveBeenLastCalledWith('/api/test/ext/finEnergy/v1/cockpit',expect.objectContaining({method:'POST'}));
});
it('decodes the negotiated snapshot before exposing it to query, report and export consumers',async()=>{
 const api=new FinEnergyApi('test'),request=query(),id='a'.repeat(64);
 const wire={payloadEncoding:'compact-v1',codecVersion:1,snapshot:{schemaVersion:1,snapshotId:'frozen',rows:{$cockpitRef:id}},evidence:{[id]:{$cockpitTable:{columns:['value','quality'],rows:[[0,'ok'],[null,'na'],[-2,'partial']]}}}};
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:true,data:wire}),{headers:{'content-type':'application/json'}}));
 expect(await api.cockpit(request)).toEqual({schemaVersion:1,snapshotId:'frozen',rows:[{value:0,quality:'ok'},{value:null,quality:'na'},{value:-2,quality:'partial'}]});
 expect(request).not.toHaveProperty('payloadEncoding');
});
it('maps invalid wire versions to the existing localizable invalid-response error',async()=>{
 const api=new FinEnergyApi('test');
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:true,data:{payloadEncoding:'compact-v1',codecVersion:2,snapshot:{},evidence:{}}}),{headers:{'content-type':'application/json'}}));
 await expect(api.cockpit(query())).rejects.toMatchObject({code:'invalid_response',sourceMessage:'FIN 返回了无效的响应。请检查项目和服务状态。'});
});
it('preserves cockpit expiry and cancellation before decoding any response',async()=>{
 const expired=vi.fn(),api=new FinEnergyApi('test',expired),abort=new Error('cancelled');abort.name='AbortError';
 vi.mocked(finCsrfFetch).mockRejectedValueOnce({status:401});await expect(api.cockpit(query())).rejects.toMatchObject({code:'unauthorized'});expect(expired).toHaveBeenCalledOnce();
 vi.mocked(finCsrfFetch).mockRejectedValueOnce(abort);await expect(api.cockpit(query())).rejects.toBe(abort);expect(expired).toHaveBeenCalledOnce();
});

it('notifies the owner on native expiry without changing default callers or forbidden/network handling',async()=>{
 const expired=vi.fn(),api=new FinEnergyApi('test',expired);
 for(const failure of [{status:401},{status:200,_isCsrfError:true}]){vi.mocked(finCsrfFetch).mockRejectedValueOnce(failure);await expect(api.catalog()).rejects.toThrow();}
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response('<html>login</html>',{headers:{'Content-Type':'text/html'}}));await expect(api.catalog()).rejects.toThrow();
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:false,error:{code:'session_expired',msg:'expired'}}),{headers:{'Content-Type':'application/json'}}));await expect(api.catalog()).rejects.toThrow();expect(expired).toHaveBeenCalledTimes(4);
 for(const failure of [{status:403},new Error('network')]){vi.mocked(finCsrfFetch).mockRejectedValueOnce(failure);await expect(api.catalog()).rejects.toThrow();}expect(expired).toHaveBeenCalledTimes(4);
});
