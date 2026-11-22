import {test,expect} from '@playwright/test';
import {readFileSync,writeFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';
const base=JSON.parse(readFileSync(new URL('../fixtures/cockpit-space-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
for(const language of ['zh-CN','en-US'])test('embedded content width keeps four cards and complete amount '+language,async({page},info)=>{
 const requests:CockpitRequest[]=[],snapshot=structuredClone(base);Object.assign(snapshot.modules.kpis!.data!.values.find(m=>m.id==='cost')!,{value:623819.708,completeValue:623819.708,knownValue:623819.708,valueType:'number',quality:'ok',valueBasis:'complete',unit:'CNY',reasonCodes:[]});
 const state=await installTransport(page,{userLocale:language,spaceSource:'fin',records:[{id:'s',kind:'space',name:'Site',nativeReadonly:true,nativeSourceKind:'site'},{id:'f',kind:'space',name:'Floor',parentId:'s',nativeReadonly:true,nativeSourceKind:'floor'},...['a','b'].map(id=>({id,kind:'meter' as const,name:id,pointId:'p'+id,nativeEquip:true,nativeTreeParentId:'f',categoryId:'c'})),{id:'c',kind:'category',name:'Electricity',unit:'kWh'}]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog*',route=>route.fulfill({json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}}));
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{const request=route.request().postDataJSON();requests.push(request);const response=structuredClone(snapshot);response.context.project='testproject';response.requestId=request.requestId;return route.fulfill({json:{ok:true,data:response}});});
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit/assets',route=>route.fulfill({json:{ok:true,data:{projectId:'testproject',manifestMod:null,selectedId:null,items:[],canWrite:false}}}));
 await page.setViewportSize({width:274,height:844});await page.goto('/#/cockpit?project=testproject');await expect(page.locator('[data-metric="cost"]')).toContainText('623,819.708');
 const evidence=[];
 for(const width of [274,344]){
  await page.setViewportSize({width,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  const geometry=await page.evaluate(()=>{
   const cards=[...document.querySelectorAll('.cockpit-kpi')].map(el=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width};});
   const amount=document.querySelector('[data-metric="cost"] .cockpit-card-number')!,walker=document.createTreeWalker(amount,NodeFilter.SHOW_TEXT),text=walker.nextNode()!,range=document.createRange();range.selectNodeContents(text);
   const value=amount.querySelector('.cockpit-value') as HTMLElement|null;
   return {cards,amountRects:range.getClientRects().length,valueScroll:value?.scrollWidth,valueWidth:value?.clientWidth,fontSize:getComputedStyle(amount).fontSize,bodyMinWidth:getComputedStyle(document.body).minWidth};
  });
  expect(geometry.cards).toHaveLength(4);expect(geometry.cards[0].y).toBe(geometry.cards[1].y);expect(geometry.cards[2].y).toBe(geometry.cards[3].y);expect(geometry.cards[2].y).toBeGreaterThan(geometry.cards[0].y);
  expect(geometry.amountRects).toBe(1);expect(geometry.valueScroll).toBeLessThanOrEqual((geometry.valueWidth||0)+1);expect(parseFloat(geometry.fontSize)).toBeGreaterThanOrEqual(14);
  evidence.push({width,...geometry});await page.screenshot({path:info.outputPath('embedded-'+language+'-'+width+'.png'),fullPage:true});
 }
 expect(requests).toHaveLength(1);writeFileSync(info.outputPath('embedded-geometry.json'),JSON.stringify({classification:'Controlled browser at actual available FIN-frame widths 274/344 CSS pixels; native field observation is separate.',evidence},null,2));
});
