import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';

const manifest=JSON.parse(readFileSync(new URL('../../../res/web/finEnergy/.vite/manifest.json',import.meta.url),'utf8')) as Record<string,{name?:string;file:string;isDynamicEntry?:boolean;css?:string[]}>;
const chunk=(name:string)=>Object.values(manifest).find(entry=>entry.name===name);
const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-space-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
const routes=['Management','MessageCenter','ReportWorkspace','CockpitPage'];

test('production build separates page code from the application shell',()=>{
 for(const name of routes)expect(chunk(name)?.isDynamicEntry,name+' must be loaded on demand').toBe(true);
});

test('prefetch and rendering share a stylesheet failure, without querying an unstyled page',async({page})=>{
 const state=await installTransport(page,{userLocale:'en-US'});
 let releaseCatalog!:()=>void;const gate=new Promise<void>(resolve=>releaseCatalog=resolve);
 const css=chunk('CockpitPage')!.css![0];let queries=0;
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog*',async route=>{await gate;await route.fulfill({json:{ok:true,data:{version,project:'testproject',user:{name:state.username,canWrite:false},records:state.records}}});});
 await page.route('**/'+css,async route=>{await route.abort('failed');releaseCatalog();});
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{queries++;const request=route.request().postDataJSON() as CockpitRequest;return route.fulfill({json:{ok:true,data:{...raw,requestId:request.requestId}}});});
 await page.goto('/#/cockpit?project=testproject');
 await expect(page.getByText('The page could not be loaded. Reload to try again.',{exact:true})).toBeVisible();
 expect(queries).toBe(0);
});

for(const language of ['zh-CN','en-US'])test('homepage starts querying while page code loads, with no unrelated pages '+language,async({page},info)=>{
 const zh=language==='zh-CN',requests:CockpitRequest[]=[],scripts:string[]=[];
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 page.on('request',request=>{if(request.resourceType()==='script')scripts.push(new URL(request.url()).pathname);});
 const state=await installTransport(page,{userLocale:language,spaceSource:'fin',records:[
  {id:'s',kind:'space',name:'Site',nativeReadonly:true,nativeSourceKind:'site'},
  {id:'f',kind:'space',name:'Floor',parentId:'s',nativeReadonly:true,nativeSourceKind:'floor'},
  {id:'a',kind:'meter',name:'Meter A',nativeEquip:true,nativeTreeParentId:'f',pointId:'pa',categoryId:'c'},
  {id:'c',kind:'category',name:'Electricity',unit:'kWh'}
 ]});
 let releaseCatalog!:()=>void;const catalogGate=new Promise<void>(resolve=>releaseCatalog=resolve);
 let catalogStarted=false;
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog*',async route=>{catalogStarted=true;await catalogGate;await route.fulfill({json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}});});
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);const snapshot=structuredClone(raw);snapshot.context.project='testproject';snapshot.requestId=request.requestId;return route.fulfill({json:{ok:true,data:snapshot}});});
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit/assets',route=>route.fulfill({json:{ok:true,data:{projectId:'testproject',manifestMod:null,selectedId:null,items:[],canWrite:false}}}));
 await page.goto('/#/cockpit?project=testproject');
 try{
  await expect.poll(()=>catalogStarted).toBe(true);
  const cockpitFile=chunk('CockpitPage')?.file;
  expect(cockpitFile,'cockpit must have its own page chunk').toBeTruthy();
  await expect.poll(()=>scripts.some(path=>path.endsWith('/'+cockpitFile))).toBe(true);
 }finally{releaseCatalog();}
 await expect(page.getByRole('heading',{name:zh?'能源经营驾驶舱':'Energy operations cockpit',exact:true})).toBeVisible();
 await expect(page.locator('.cockpit-trend canvas')).toBeVisible();
 expect(requests).toHaveLength(1);expect(requests[0].modules).toHaveLength(9);
 for(const name of routes.filter(name=>name!=='CockpitPage'))expect(scripts.some(path=>path.endsWith('/'+chunk(name)?.file)),name+' was fetched before navigation').toBe(false);
 await page.setViewportSize({width:320,height:844});
 await expect(page.locator('.cockpit-number').first()).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:info.outputPath('homepage-'+language+'-320.png'),fullPage:true});
 await page.setViewportSize({width:1440,height:1000});
 await page.getByRole('navigation',{name:zh?'主导航':'Main navigation',exact:true}).getByRole('button',{name:zh?'消息中心':'Message center',exact:true}).click();
 await expect(page.getByRole('heading',{name:zh?'消息中心':'Message center',exact:true})).toBeVisible();
 expect(scripts.some(path=>path.endsWith('/'+chunk('MessageCenter')!.file))).toBe(true);
 await page.getByRole('navigation',{name:zh?'主导航':'Main navigation',exact:true}).getByRole('button',{name:zh?'设置':'Settings',exact:true}).click();
 await expect(page.getByRole('heading',{name:zh?'计量对象管理':'Metering objects',exact:true})).toBeVisible();
 expect(errors).toEqual([]);
});

for(const language of ['zh-CN','en-US'])test('a failed page download retains localized recovery and navigation '+language,async({page},info)=>{
 const zh=language==='zh-CN';await installTransport(page,{userLocale:language});
 const managementFile=chunk('Management')!.file;
 await page.route('**/'+managementFile,route=>route.abort('failed'));
 await page.goto('/#/tree?project=testproject');
 await expect(page.getByText(zh?'页面加载失败，请重新加载。':'The page could not be loaded. Reload to try again.',{exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:zh?'重新加载页面':'Reload page',exact:true})).toBeVisible();
 await page.screenshot({path:info.outputPath('page-download-failure-'+language+'.png'),fullPage:true});
 await page.getByRole('navigation',{name:zh?'主导航':'Main navigation',exact:true}).getByRole('button',{name:zh?'消息中心':'Message center',exact:true}).click();
 await expect(page.getByRole('heading',{name:zh?'消息中心':'Message center',exact:true})).toBeVisible();
});
