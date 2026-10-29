import {afterEach,expect,it,vi} from 'vitest';
import {finCsrfFetch} from 'haystack-nclient';
import {loadFinLocale} from './session';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));
afterEach(()=>vi.clearAllMocks());
const location={hash:'#/profile?project=FIN%20Project',search:'?enerCubixLang=zh-CN',pathname:'/pod/enerCubix/res/web/enerCubix/index-0.12.16.html'};

it('uses an authenticated no-cache request for the active project and retains the exact FIN locale',async()=>{
 vi.mocked(finCsrfFetch).mockResolvedValue(new Response(JSON.stringify({ok:true,data:{locale:'en-GB'}})));
 expect(await loadFinLocale(location)).toBe('en-GB');
 expect(finCsrfFetch).toHaveBeenCalledWith('/api/FIN%20Project/ext/enerCubix/v1/session',expect.objectContaining({credentials:'same-origin',method:'GET',cache:'no-store'}));
});
it.each([
 [401,'text/html','<h1>Sign in</h1>'],
 [200,'text/html','<h1>Sign in</h1>'],
 [500,'application/json',JSON.stringify({ok:false})],
 [200,'application/json',JSON.stringify({ok:true,data:{locale:''}})],
 [200,'application/json',JSON.stringify({ok:true,data:{locale:12}})]
])('does not continue with browser language when FIN returns %s %s',async(status,type,body)=>{
 vi.mocked(finCsrfFetch).mockResolvedValue(new Response(body,{status,headers:{'Content-Type':type}}));
 await expect(loadFinLocale(location)).rejects.toThrow();
});
it('does not read a session when no project was specified',async()=>{
 await expect(loadFinLocale({hash:'',search:'',pathname:'/'})).rejects.toThrow();
 expect(finCsrfFetch).not.toHaveBeenCalled();
});
