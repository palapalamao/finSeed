import {test,expect} from '@playwright/test';
import {readFileSync,writeFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';
const raw=JSON.parse(readFileSync(new URL('../fixtures/cockpit-space-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;

for(const language of ['zh-CN','en-US'])test('visible quality and explicit all-site draft '+language,async({page},testInfo)=>{
 const zh=language==='zh-CN',state=await installTransport(page,{userLocale:language,canWrite:false,spaceSource:'fin',records:[
  {id:'s',kind:'space',name:'North campus',nativeSourceKind:'site',nativeReadonly:true},
  {id:'south',kind:'space',name:'South campus',nativeSourceKind:'site',nativeReadonly:true},
  {id:'hidden',kind:'space',name:'Hidden campus',nativeSourceKind:'site',nativeHidden:true,nativeReadonly:true},
  {id:'f',kind:'space',name:'Floor',parentId:'s',nativeSourceKind:'floor',nativeReadonly:true},
  {id:'a',kind:'meter',name:'Meter A',categoryId:'c',spaceId:'f',pointId:'pa'},
  {id:'b',kind:'meter',name:'Meter B',categoryId:'c',spaceId:'f',pointId:'pb'},
  {id:'c',kind:'category',name:'Electricity',unit:'kWh'}
 ]});
 await page.route('**/api/testproject/ext/enerCubix/v1/catalog',route=>route.fulfill({json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}}));
 const requests:CockpitRequest[]=[];
 await page.route('**/api/testproject/ext/enerCubix/v1/cockpit',route=>{
  const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);
  const snapshot=structuredClone(raw);snapshot.snapshotId='quality-sites-'+requests.length;snapshot.requestId=request.requestId;snapshot.context.project='testproject';snapshot.context.reportScope=request.reportScope;
  Object.values(snapshot.modules).forEach(module=>{module.status='ok';});snapshot.modules.time!.status='partial';snapshot.modules.balance!.status='error';snapshot.modules.efficiency!.status='unavailable';
  return route.fulfill({json:{ok:true,data:snapshot}});
 });
 await page.goto('/#/cockpit?project=testproject');await expect.poll(()=>requests.length).toBe(1);await expect(page.locator('.cockpit-number')).toHaveText('30 kWh');
 expect(requests[0].reportScope.nodeIds).toEqual(['s']);
 await page.locator('.cockpit-conditions-trigger').click();const applied=await page.locator('.cockpit-project-line').textContent();
 await page.getByRole('button',{name:zh?'全部可访问站点':'All accessible sites',exact:true}).click();
 expect(requests).toHaveLength(1);await expect(page.locator('.cockpit-project-line')).toHaveText(applied!);await expect(page.locator('.cockpit-number')).toHaveText('30 kWh');
 await page.locator('.cockpit-query-submit').click();await expect.poll(()=>requests.length).toBe(2);
 expect(requests[1].reportScope).toEqual({dimension:'space',nodeIds:['s','south'],selectionIntent:'range'});
 await page.getByRole('combobox',{name:zh?'统计范围':'Statistical scope',exact:true}).click();
 const dropdown=page.locator('.ant-select-dropdown:visible');
 await expect(dropdown.getByText('Hidden campus',{exact:true})).toHaveCount(0);
 await dropdown.getByText('South campus',{exact:true}).click();await page.keyboard.press('Escape');expect(requests).toHaveLength(2);
 await page.locator('.cockpit-query-submit').click();await expect.poll(()=>requests.length).toBe(3);expect(requests[2].reportScope.nodeIds).toEqual(['s']);
 await page.locator('.cockpit-conditions-trigger').click();
 const quality=page.locator('.cockpit-visual .cockpit-quality-summary'),captures=[];
 for(const width of [1920,1366,390,320]){
  await page.setViewportSize({width,height:width<500?900:1080});
  await page.locator('.cockpit-conditions-trigger').click();
  await expect(page.getByRole('button',{name:zh?'全部可访问站点':'All accessible sites',exact:true})).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.locator('.cockpit-conditions-trigger').click();
  const visible=quality.locator(':scope > p');
  for(const text of zh?['时间','部分数据可用','计量平衡','读取失败','能效','暂不可用']:['Time','Partial data available','Metering balance','Read failed','Efficiency','Unavailable'])await expect(visible).toContainText(text);
  await expect(quality.locator(':scope > details')).not.toHaveAttribute('open','');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  const file=testInfo.outputPath('quality-'+language+'-'+width+'.png');await quality.screenshot({path:file});captures.push({width,file});
 }
 expect(requests).toHaveLength(3);writeFileSync(testInfo.outputPath('evidence.json'),JSON.stringify({classification:'Controlled local transport only; no FIN browser or onsite writes',requests,captures}));
});
