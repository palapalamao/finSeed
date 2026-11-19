import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import {createNavigation,encodeNavigation} from '../../src/cockpitNavigation';
import type {CockpitSnapshot} from '../../src/cockpitTypes';
const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-efficiency-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
for(const language of ['zh-CN','en-US'])test('COP shows total ratio and opens the frozen professional report '+language,async({page})=>{
 const state=await installTransport(page,{userLocale:language,records:[{id:'in',kind:'meter',name:'输入电表原名',mod:'2026-10-01T00:00:00Z',pointId:'pi',categoryId:'elec'},{id:'out',kind:'meter',name:'供冷表原名',mod:'2026-10-01T00:00:00Z',pointId:'po',categoryId:'heat'},...['pi','po'].map(id=>({id,kind:'nativePoint',name:id,his:true})),{id:'elec',kind:'category',name:'电力原名',unit:'kWh'},{id:'heat',kind:'category',name:'冷量原名',unit:'kWh'},{id:'plant',kind:'group',name:'Plant'},{id:'cop',kind:'cop',name:'Plant COP',numeratorId:'out',denominatorId:'in',mod:'2026-10-01T00:00:00Z'}]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog',route=>route.fulfill({status:200,json:{ok:true,data:{project:'testproject',version,user:{name:state.username,canWrite:false},records:state.records}}}));
 let calls=0;await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{calls++;const snapshot=structuredClone(raw);snapshot.context.project='testproject';snapshot.requestId=route.request().postDataJSON().requestId;return route.fulfill({status:200,json:{ok:true,data:snapshot}});});
 const parent={...raw,context:{...raw.context,project:'testproject'}},navigation=createNavigation(parent,'profile',{selectedFace:'efficiency',presentationMode:false,scrollY:0,draft:{scope:parent.context.reportScope,categoryId:'elec',preset:'custom'}});
 await page.goto('/#/cockpit?project=testproject&navigation='+encodeURIComponent(encodeNavigation(navigation)));const cop=page.locator('[data-cop="cop"]');await expect(cop.locator('.cockpit-card-number')).toHaveText('4 COP');await expect(cop).toContainText('96,000');await expect(cop).toContainText('24,000');await expect(cop.locator('canvas')).toBeVisible();expect(calls).toBe(1);
 await page.getByRole('button',{name:language==='zh-CN'?'打开 COP 专业报告':'Open COP report',exact:true}).click();await expect(page).toHaveURL(/#.*cop/);await expect(page.locator('.report-chart canvas')).toBeVisible();expect(state.requests.filter(request=>request.path==='report')).toHaveLength(0);
 await page.getByRole('button',{name:language==='zh-CN'?'返回驾驶舱':'Return to cockpit',exact:true}).click();await expect(page.locator('[data-cop="cop"] .cockpit-card-number')).toHaveText('4 COP');expect(calls).toBe(1);
 for(const width of [320,390]){await page.setViewportSize({width,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);await page.screenshot({path:'test-results/cockpit-efficiency-'+language+'-'+width+'.png',fullPage:true});}
});
