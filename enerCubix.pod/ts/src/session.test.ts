import {afterEach,expect,it,vi} from 'vitest';
import {finCsrfFetch} from 'haystack-nclient';
import {loadFinSession} from './session';
import {initializeLocale,t} from './i18n';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));
afterEach(()=>vi.clearAllMocks());
const location={hash:'#/profile?project=FIN%20Project',search:'?enerCubixLang=zh-CN',pathname:'/pod/enerCubix/res/web/enerCubix/index-0.12.16.html'};

it('uses an authenticated no-cache request for the active project and retains the exact FIN locale',async()=>{
 vi.mocked(finCsrfFetch).mockResolvedValue(new Response(JSON.stringify({ok:true,data:{locale:'en-GB',username:'alice'}})));
 expect(await loadFinSession(location)).toEqual({locale:'en-GB',username:'alice'});
 expect(finCsrfFetch).toHaveBeenCalledWith('/api/FIN%20Project/ext/enerCubix/v1/session',expect.objectContaining({credentials:'same-origin',method:'GET',cache:'no-store'}));
});
it.each([
 [401,'text/html','<h1>Sign in</h1>'],
 [200,'text/html','<h1>Sign in</h1>'],
 [500,'application/json',JSON.stringify({ok:false})],
 [200,'application/json',JSON.stringify({ok:true,data:{locale:''}})],
 [200,'application/json',JSON.stringify({ok:true,data:{locale:12}})],
 [200,'application/json',JSON.stringify({ok:true,data:{locale:'en'}})],
 [200,'application/json',JSON.stringify({ok:true,data:{locale:'en',username:''}})]
])('does not continue with browser language when FIN returns %s %s',async(status,type,body)=>{
 vi.mocked(finCsrfFetch).mockResolvedValue(new Response(body,{status,headers:{'Content-Type':type}}));
 await expect(loadFinSession(location)).rejects.toThrow();
});
it('does not read a session when no project was specified',async()=>{
 await expect(loadFinSession({hash:'',search:'',pathname:'/'})).rejects.toThrow();
 expect(finCsrfFetch).not.toHaveBeenCalled();
});

it.each(['zh-CN','en-US'])('distinguishes FIN authentication, permission and network failures in %s',async language=>{
 initializeLocale(language);
 for(const error of [Object.assign(new Error('Cannot acquire attest key'),{_isCsrfError:true,status:200}),{status:401}]){
  vi.mocked(finCsrfFetch).mockRejectedValueOnce(error);
  await expect(loadFinSession(location)).rejects.toThrow(t('FIN 会话已失效，请在 FIN 中重新登录。'));
 }
 vi.mocked(finCsrfFetch).mockRejectedValueOnce({status:403});
 await expect(loadFinSession(location)).rejects.toThrow(t('当前 FIN 会话无权访问此项目。'));
 vi.mocked(finCsrfFetch).mockRejectedValueOnce(new TypeError('Failed to fetch'));
 await expect(loadFinSession(location)).rejects.toThrow(t('无法连接 FIN，请检查网络与当前会话。'));
});

it.each(['zh-CN','en-US'])('classifies native login HTML and permission responses in %s',async language=>{
 initializeLocale(language);
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response('<h1>Login</h1>',{headers:{'Content-Type':'text/html'}}));
 await expect(loadFinSession(location)).rejects.toThrow(t('FIN 会话已失效，请在 FIN 中重新登录。'));
 vi.mocked(finCsrfFetch).mockResolvedValueOnce(new Response('{}',{status:403,headers:{'Content-Type':'application/json'}}));
 await expect(loadFinSession(location)).rejects.toThrow(t('当前 FIN 会话无权访问此项目。'));
});
