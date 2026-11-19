import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import {createNavigation,encodeNavigation} from '../../src/cockpitNavigation';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';
const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-area-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
for(const language of ['zh-CN','en-US'])test('shared-floor denominator, source revision and no-query evidence '+language,async({page})=>{
 const state=await installTransport(page,{userLocale:language,records:[{id:'floor',mod:'floor-v1',kind:'space',name:'楼层原名',nativeReadonly:true,area:1000},{id:'lighting',kind:'meter',name:'照明原名',categoryId:'c',pointId:'pl',areaSource:'space',areaSpaceId:'floor'},{id:'power',kind:'meter',name:'动力原名',categoryId:'c',pointId:'pp',areaSource:'space',areaSpaceId:'floor'},{id:'pl',kind:'nativePoint',name:'照明主点',his:true},{id:'pp',kind:'nativePoint',name:'动力主点',his:true},{id:'c',kind:'category',name:'电力原名',unit:'kWh'}]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog',route=>route.fulfill({status:200,json:{ok:true,data:{version,project:'testproject',user:{name:state.username,canWrite:false},records:state.records}}}));
 const requests:CockpitRequest[]=[];await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);const snapshot=structuredClone(raw);snapshot.requestId=request.requestId;snapshot.context.project='testproject';return route.fulfill({status:200,json:{ok:true,data:snapshot}});});
 const parent={...raw,context:{...raw.context,project:'testproject'}},navigation=createNavigation(parent,'profile',{selectedFace:'space',presentationMode:false,scrollY:0,draft:{scope:parent.context.reportScope,categoryId:'c',preset:'custom'}});
 await page.goto('/#/cockpit?project=testproject&navigation='+encodeURIComponent(encodeNavigation(navigation)));
 await expect(page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true})).toBeVisible();await expect(page.locator('.cockpit-number')).toHaveText('300 kWh');await expect(page.getByRole('button',{name:language==='zh-CN'?'刷新数据':'Refresh data',exact:true})).toBeVisible();
 await page.locator('[data-metric="areaIntensity"]>details>summary').click();const evidence=page.locator('.cockpit-area-evidence');await expect(evidence).toContainText('300 kWh ÷ 1,000 m² = 0.3 kWh/m²');await expect(evidence).toContainText(raw.modules.kpis!.data!.values.find(value=>value.id==='areaIntensity')!.details!.areaResolution!.sourceRevisions[0].mod!);await expect(evidence.locator('tbody tr')).toHaveCount(1);await expect(evidence).toContainText(language==='zh-CN'?'仅计一次':'counted once');expect(requests).toHaveLength(1);
 for(const width of [320,390]){await page.setViewportSize({width,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);await page.screenshot({path:'test-results/cockpit-area-'+language+'-'+width+'.png',fullPage:true});}expect(requests).toHaveLength(1);
});
