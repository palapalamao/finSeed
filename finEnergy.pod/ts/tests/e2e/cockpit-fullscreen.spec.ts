import {test,expect,type Page} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport} from './fixtures';

const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-space-response.json',import.meta.url),'utf8'));
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
async function setup(page:Page,language:string){
 const state=await installTransport(page,{userLocale:language,spaceSource:'fin',canWrite:false,records:[{id:'s',kind:'space',name:'Site',nativeReadonly:true,nativeSourceKind:'site'},{id:'f',kind:'space',name:'Floor',parentId:'s',nativeReadonly:true,nativeSourceKind:'floor'},...['a','b'].map(id=>({id,kind:'meter' as const,name:id,pointId:'p'+id,categoryId:'c',nativeEquip:true,nativeTreeParentId:'f'})),{id:'c',kind:'category',name:'Electricity',unit:'kWh'}]});
 let queries=0;
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog*',route=>route.fulfill({json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}}));
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{queries++;const snapshot=structuredClone(raw);snapshot.context.project='testproject';snapshot.requestId=route.request().postDataJSON().requestId;return route.fulfill({json:{ok:true,data:snapshot}});});
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit/assets',route=>route.fulfill({json:{ok:true,data:{projectId:'testproject',manifestMod:null,selectedId:null,items:[],canWrite:false}}}));
 await page.route('**/__fullscreen-host',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html><body style="margin:0"><iframe title="FinEnergy fullscreen acceptance" src="/#/cockpit?project=testproject" allow="fullscreen" allowfullscreen style="width:100%;height:100vh;border:0"></iframe></body></html>'}));
 await page.goto('/__fullscreen-host');
 const app=page.frameLocator('iframe[title="FinEnergy fullscreen acceptance"]');
 await expect(app.locator('.cockpit-number')).toHaveText('30 kWh');
 const enter=async()=>{await app.locator('.cockpit-more-tools > summary').click();await app.getByRole('button',{name:language==='zh-CN'?'全屏汇报':'Full-screen presentation',exact:true}).click();};
 const invariant=async()=>{await expect(app.locator('.cockpit-snapshot')).toHaveAttribute('data-cockpit-snapshot',raw.snapshotId);expect(queries).toBe(1);};
 const isFullscreen=async()=>({host:await page.evaluate(()=>!!document.fullscreenElement),app:await app.locator('html').evaluate(el=>!!el.ownerDocument.fullscreenElement)});
 return {app,enter,invariant,isFullscreen};
}
for(const language of ['zh-CN','en-US']){
 const zh=language==='zh-CN';
 test('iframe fullscreen Escape and exit button preserve one snapshot '+language,async({page},info)=>{
  const h=await setup(page,language);await h.enter();
  await expect.poll(h.isFullscreen).toEqual({host:true,app:true});
  await page.keyboard.press('Escape');
  await expect.poll(h.isFullscreen).toEqual({host:false,app:false});
  await expect(h.app.locator('.cockpit-presentation')).toHaveCount(0);await h.invariant();
  await page.screenshot({path:info.outputPath('escape-exited-'+language+'.png')});
  await h.enter();await expect.poll(h.isFullscreen).toEqual({host:true,app:true});
  await h.app.getByRole('button',{name:zh?'退出全屏':'Exit fullscreen',exact:true}).click();
  await expect.poll(h.isFullscreen).toEqual({host:false,app:false});await expect(h.app.locator('.cockpit-presentation')).toHaveCount(0);await h.invariant();
 });
 test('iframe fullscreen refusal retains localized recovery '+language,async({page},info)=>{
  await page.addInitScript(()=>{Element.prototype.requestFullscreen=async()=>{throw new DOMException('Controlled fullscreen refusal','NotAllowedError');};});
  const h=await setup(page,language);await h.enter();
  await expect.poll(h.isFullscreen).toEqual({host:false,app:false});
  await expect(h.app.locator('.cockpit-presentation')).toBeVisible();
  await expect(h.app.getByText(zh?'无法进入全屏，已保留汇报布局，可使用退出按钮。':'Full screen is unavailable. The presentation layout remains available with an exit button.',{exact:true})).toBeVisible();
  await page.screenshot({path:info.outputPath('fullscreen-refused-'+language+'.png')});
  await h.app.getByRole('button',{name:zh?'退出汇报布局':'Exit presentation layout',exact:true}).click();
  await expect(h.app.locator('.cockpit-presentation')).toHaveCount(0);await h.invariant();
 });
}
