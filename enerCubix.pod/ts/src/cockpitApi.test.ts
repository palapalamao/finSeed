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
