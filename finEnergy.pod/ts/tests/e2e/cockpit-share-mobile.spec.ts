import {expect,test} from '@playwright/test';
import {readFileSync,writeFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import {createNavigation,encodeNavigation} from '../../src/cockpitNavigation';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';

const source=JSON.parse(readFileSync(new URL('../fixtures/cockpit-faces-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
const longNames=[
 '综合园区配电系统照明与插座用电 International lighting and socket distribution',
 '动力设备生产车间动力用电 InternationalProcessEquipmentAndMechanicalPowerDistribution',
 '空调冷热源及公共辅助设备 Heating cooling and common auxiliary equipment',
 '真实零值 Zero consumption',
 'NA 保留 NA retained',
 '缺测保留 Missing readings retained'
];

for(const language of ['zh-CN','en-US'])for(const variant of ['standard','long-and-partial'])test('end-use names amounts and shares stay readable '+variant+' '+language,async({page},info)=>{
 const snapshot=structuredClone(source),ref=snapshot.modules.endUse!.data!.reportRef;
 const shares=snapshot.reports[ref].extra!.utilityShares as Record<string,unknown>[];
 if(variant==='long-and-partial'){
  const values=[12345678.125,180,33.5,0,null,null];
  const total=values.reduce<number>((sum,value)=>sum+(value??0),0);
  shares.splice(0,shares.length,...values.map((value,index)=>({...structuredClone(shares[index%2]),id:'share-'+index,utilityId:'use-'+index,name:longNames[index],value,knownValue:value,valueType:index===4?'na':value===null?'null':'number',knownValueType:index===4?'na':value===null?'null':'number',quality:index===4?'na':value===null?'missing':'ok',knownQuality:index===4?'na':value===null?'missing':'ok',percentage:value===null?null:value/total*100,knownPercentage:value===null?null:value/total*100})));
 }
 const state=await installTransport(page,{userLocale:language,records:[
  {id:'a',kind:'meter',name:'设备A原名',pointId:'pa',categoryId:'c',utilityId:'lighting'},
  {id:'b',kind:'meter',name:'设备B原名',pointId:'pb',categoryId:'c',utilityId:'motive'},
  {id:'pa',kind:'nativePoint',name:'主点A',his:true},
  {id:'pb',kind:'nativePoint',name:'主点B',his:true},
  {id:'c',kind:'category',name:'电力原名',unit:'kWh'},
  ...shares.map(row=>({id:String(row.utilityId),kind:'utility' as const,name:String(row.name),categoryId:'c'}))
 ]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog*',route=>route.fulfill({json:{ok:true,data:{project:'testproject',version,user:{name:state.username,canWrite:false},records:state.records}}}));
 const requests:CockpitRequest[]=[];
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{
  const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);
  return route.fulfill({json:{ok:true,data:{...snapshot,context:{...snapshot.context,project:'testproject'},requestId:request.requestId,snapshotId:'share-mobile'}}});
 });
 const parent={...snapshot,context:{...snapshot.context,project:'testproject'}};
 const navigation=createNavigation(parent,'profile',{selectedFace:'endUse',presentationMode:false,scrollY:0,draft:{scope:parent.context.reportScope,categoryId:'c',preset:'custom'}});
 await page.goto('/#/cockpit?project=testproject&navigation='+encodeURIComponent(encodeNavigation(navigation)));
 const panel=page.locator('[data-face="endUse"]');
 await expect(panel.locator('canvas')).toBeVisible();
 const legend=panel.getByRole('list',{name:language==='zh-CN'?'分项能耗占比':'End-use energy shares'});
 const captures:unknown[]=[];
 for(const width of [320,390,1366,1920]){
  await page.setViewportSize({width,height:width>=1366?1080:844});
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  if(width<=390){
   await expect(legend).toBeVisible();
   const items=legend.getByRole('listitem');await expect(items).toHaveCount(shares.length);
   for(const [index,row] of shares.entries()){
    const item=items.nth(index);
    await expect(item.locator('.cockpit-share-name')).toHaveText(String(row.name));
    const amount=row.knownValueType==='na'?'NA':row.knownValue===null?'—':new Intl.NumberFormat(language,{maximumFractionDigits:3}).format(Number(row.knownValue));
    const percentage=typeof row.knownPercentage==='number'?new Intl.NumberFormat(language,{maximumFractionDigits:2}).format(row.knownPercentage)+'%':'—';
    await expect(item.locator('.cockpit-share-value')).toHaveText(amount);
    await expect(item.locator('.cockpit-share-percentage')).toHaveText(percentage);
    await expect(item).toContainText('kWh');
    await expect(item.locator('.cockpit-share-value')).toBeVisible();await expect(item.locator('.cockpit-share-percentage')).toBeVisible();
    // Read both rectangles in one layout frame; sequential browser calls can straddle a resize.
    const rowOffset=await item.evaluate(element=>Math.abs(element.querySelector('.cockpit-share-value')!.getBoundingClientRect().y-element.querySelector('.cockpit-share-percentage')!.getBoundingClientRect().y));
    expect(rowOffset,'amount and share should remain paired in one row').toBeLessThanOrEqual(2);
   }
   const layout=await legend.evaluate(element=>[...element.querySelectorAll<HTMLElement>('.cockpit-share-name,.cockpit-share-value,.cockpit-share-percentage')].map(field=>{
    const box=field.getBoundingClientRect(),range=document.createRange();range.selectNodeContents(field);
    return {text:field.textContent,client:field.clientWidth,scroll:field.scrollWidth,box:{x:box.x,right:box.right,bottom:box.bottom},glyphs:[...range.getClientRects()].map(r=>({x:r.x,right:r.right,bottom:r.bottom})),overflow:getComputedStyle(field).textOverflow};
   }));
   for(const field of layout){
    expect(field.scroll,'full names and values must fit without horizontal scrolling').toBeLessThanOrEqual(field.client+1);
    expect(field.overflow).not.toBe('ellipsis');
    for(const glyph of field.glyphs){expect(glyph.x).toBeGreaterThanOrEqual(field.box.x-1);expect(glyph.right).toBeLessThanOrEqual(field.box.right+1);expect(glyph.bottom).toBeLessThanOrEqual(field.box.bottom+1);}
   }
   captures.push({width,layout});
  }else await expect(legend).toBeHidden();
  await expect(page.locator('.cockpit-snapshot')).toHaveAttribute('data-cockpit-snapshot','share-mobile');
  expect(requests).toHaveLength(1);
  await page.evaluate(()=>window.scrollTo(0,0));
  await page.screenshot({path:info.outputPath('end-use-'+width+'.png'),fullPage:true});
 }
 // Returning from the professional view restores the same cockpit snapshot.
 await panel.getByRole('button',{name:language==='zh-CN'?'打开分项用量报告':'Open end-use usage report',exact:true}).click();
 await expect(page).toHaveURL(/#\/utility/);
 await expect(page.locator('.cockpit-share-legend')).toHaveCount(0);
 await page.getByRole('button',{name:language==='zh-CN'?'返回驾驶舱':'Return to cockpit',exact:true}).click();
 await expect(panel).toBeVisible();expect(requests).toHaveLength(1);
 writeFileSync(info.outputPath('share-layout.json'),JSON.stringify({classification:'Controlled production preview; no FIN business data or native performance claim',language,variant,shares,captures,requests},null,2));
});
