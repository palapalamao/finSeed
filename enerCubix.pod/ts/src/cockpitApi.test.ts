import {expect,it,vi} from 'vitest';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));
import {finCsrfFetch} from 'haystack-nclient';
import {EnerCubixApi} from './api';

it('reads the cockpit with native FIN POST credentials and a cancellable request',async()=>{
 const api=new EnerCubixApi('building one');
 expect(api).toHaveProperty('cockpit',expect.any(Function));
 const controller=new AbortController();
 const request={schemaVersion:1,requestId:'one',reportScope:{dimension:'space',nodeIds:['site'],selectionIntent:'range'},focusCategoryId:'electricity',time:{preset:'thisMonth',period:'day'},modules:['kpis','trend']};
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:true,data:{snapshotId:'snapshot'}}),{headers:{'content-type':'application/json'}}));
 await (api as unknown as {cockpit:(request:unknown,signal:AbortSignal)=>Promise<unknown>}).cockpit(request,controller.signal);
 expect(finCsrfFetch).toHaveBeenLastCalledWith('/api/building%20one/ext/enerCubix/v1/cockpit',expect.objectContaining({method:'POST',credentials:'same-origin',signal:controller.signal,body:JSON.stringify(request)}));
});

it('notifies the owner on native expiry without changing default callers or forbidden/network handling',async()=>{
 const expired=vi.fn(),api=new EnerCubixApi('test',expired);
 for(const failure of [{status:401},{status:200,_isCsrfError:true}]){vi.mocked(finCsrfFetch).mockRejectedValueOnce(failure);await expect(api.catalog()).rejects.toThrow();}
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response('<html>login</html>',{headers:{'Content-Type':'text/html'}}));await expect(api.catalog()).rejects.toThrow();
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response(JSON.stringify({ok:false,error:{code:'session_expired',msg:'expired'}}),{headers:{'Content-Type':'application/json'}}));await expect(api.catalog()).rejects.toThrow();expect(expired).toHaveBeenCalledTimes(4);
 for(const failure of [{status:403},new Error('network')]){vi.mocked(finCsrfFetch).mockRejectedValueOnce(failure);await expect(api.catalog()).rejects.toThrow();}expect(expired).toHaveBeenCalledTimes(4);
});
