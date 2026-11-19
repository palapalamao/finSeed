import {test,expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import type {CockpitSnapshot,CockpitRequest} from '../../src/cockpitTypes';
const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-space-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
for(const language of ['zh-CN','en-US'])test('snapshot default focus stays local, clears and recovers on new snapshot '+language,async({page},info)=>{
 const zh=language==='zh-CN',requests:CockpitRequest[]=[],control={snapshot:structuredClone(raw),revision:0};
 const state=await installTransport(page,{userLocale:language,spaceSource:'fin',canWrite:false,records:[{id:'s',kind:'space',name:'Site',nativeReadonly:true,nativeSourceKind:'site'},{id:'f',kind:'space',name:'Floor',parentId:'s',nativeReadonly:true,nativeSourceKind:'floor'},...['a','b'].map(id=>({id,kind:'meter' as const,name:id,nativeEquip:true,nativeTreeParentId:'f',pointId:'p'+id,categoryId:'c'})),{id:'c',kind:'category',name:'Electricity',unit:'kWh'}]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog',route=>route.fulfill({json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}}));
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);const snapshot=structuredClone(control.snapshot);snapshot.snapshotId+='-'+(++control.revision);snapshot.context.project='testproject';snapshot.requestId=request.requestId;return route.fulfill({json:{ok:true,data:snapshot}});});
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit/assets',route=>route.fulfill({json:{ok:true,data:{projectId:'testproject',items:[],selectedId:null,canWrite:false}}}));
 await page.goto('/#/cockpit?project=testproject');const panel=page.locator('.cockpit-focus-panel');
 await expect(panel.locator('summary').first()).toBeVisible();await expect(panel.locator('.cockpit-focus-title')).toContainText('Site');expect(requests).toHaveLength(1);expect(requests[0].reportScope.nodeIds).toEqual(['s']);
 await panel.locator('summary').first().click();await page.getByRole('button',{name:zh?'清除焦点':'Clear focus',exact:true}).click();await expect(panel).toHaveCount(0);await expect(page.locator('[data-space-object="s"]')).toHaveAttribute('aria-pressed','false');expect(requests).toHaveLength(1);
 await page.locator('[data-space-object="f"]').click();await expect(panel.locator('.cockpit-focus-title')).toContainText('Floor');
 await page.locator('.cockpit-query-submit').click();await expect.poll(()=>requests.length).toBe(2);await expect(panel.locator('.cockpit-focus-title')).toContainText('Floor');
 // The next packet omits the old floor. Its invalid focus falls back locally.
 control.snapshot.modules.space!.data!.nodes=control.snapshot.modules.space!.data!.nodes.filter(node=>node.nodeKind!=='floor');
 const site=control.snapshot.modules.space!.data!.nodes.find(node=>node.nodeKind==='site')!;Object.assign(site,{name:'Site / 某某医学院附属医院综合园区能源管理中心（真实业务长名称保持原文）',value:30,knownValue:30,completeValue:null,valueBasis:'knownSubtotal',quality:'partial'});
 await page.locator('.cockpit-query-submit').click();await expect.poll(()=>requests.length).toBe(3);await expect(panel.locator('.cockpit-focus-title')).toContainText('Site');await expect(panel).toContainText(zh?'已有用量小计':'Known usage subtotal');await expect(panel).toContainText('30 kWh');
 expect(requests.every(request=>JSON.stringify(request.reportScope)===JSON.stringify(requests[0].reportScope))).toBe(true);
 for(const width of [390,320]){await page.setViewportSize({width,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);const boxes=await page.locator('.cockpit-kpi').evaluateAll(nodes=>nodes.map(node=>({x:node.getBoundingClientRect().x,y:node.getBoundingClientRect().y})));expect(boxes[0].y).toBe(boxes[1].y);expect(boxes[2].y).toBe(boxes[3].y);await page.screenshot({path:info.outputPath('reference-focus-'+language+'-'+width+'.png'),fullPage:true});}
 expect(requests).toHaveLength(3);
});
