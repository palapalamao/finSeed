import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {ChangeMessage} from '../../src/changeMessages';

for(const language of ['zh-CN','en-US'])test(`message center keeps alarms and shows paginated changes in ${language}`,async({page},testInfo)=>{
 const zh=language==='zh-CN';const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 await page.addInitScript(value=>localStorage.setItem('enerCubix.locale.v1',value),language);
 const state=await installTransport(page,{canWrite:false});
 state.records.push({id:'master2',kind:'totalMeter',name:'备用总电表'});
 const changes:ChangeMessage[]=Array.from({length:31},(_,index)=>({id:`change-${index}`,ts:`2026-10-26T02:${String(index).padStart(2,'0')}:00+08:00`,action:'updated',category:'relationship',objectId:'meter1',objectName:`分表变更${index+1}`,objectKind:'meter',actor:index?'operator1':undefined,changes:[{field:'meterParentId',before:'master1',after:'master2'},{field:'includeInTotals',before:true,after:false}]}));
 const offsets:number[]=[];
 await page.route('**/messages/changes?**',async route=>{
  expect(route.request().method()).toBe('GET');
  const query=new URL(route.request().url()).searchParams,offset=Number(query.get('offset')),limit=Number(query.get('limit'));
  offsets.push(offset);await route.fulfill({json:{ok:true,data:{items:changes.slice(offset,offset+limit),total:changes.length,offset,limit}}});
 });
 // Existing bookmarks remain valid and lead to the renamed center.
 await openView(page,'alarms');
 await expect(page.getByRole('heading',{name:zh?'消息中心':'Message center',exact:true})).toBeVisible();
 await expect(page.getByRole('heading',{name:zh?'能耗报警':'Energy alarms',exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:zh?'确认报警':'Acknowledge alarm',exact:true})).toBeDisabled();
 await page.getByRole('tab',{name:zh?'重要变更':'Important changes',exact:true}).click();
 const section=page.locator('.change-messages');
 await expect(section).toContainText('分表变更1');
 await expect(section).toContainText(zh?'未记录':'Not recorded');
 await section.locator('.ant-table-row-expand-icon').first().click();
 await expect(section).toContainText('备用总电表');
 await expect(section).toContainText(zh?'关闭':'Off');
 await expect(section.getByRole('button',{name:zh?'确认报警':'Acknowledge alarm',exact:true})).toHaveCount(0);
 await section.locator('.ant-pagination-item-2').click();
 await expect(section).toContainText('分表变更31');
 await expect(section).not.toContainText('分表变更1');
 expect(offsets).toEqual([0,30]);
 await section.getByRole('button',{name:zh?'刷新记录':'Refresh records',exact:true}).click();
 await expect.poll(()=>offsets.length).toBe(3);
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:960});
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(section.getByText('分表变更31',{exact:true})).toBeVisible();
  await page.screenshot({path:testInfo.outputPath(`message-center-${language}-${width}.png`),fullPage:true});
 }
 expect(state.requests.filter(request=>request.path==='alarms/ack')).toHaveLength(0);
 expect(errors).toEqual([]);
});

test('change read failures are visible and a refresh can show an empty history',async({page})=>{
 await page.addInitScript(()=>localStorage.setItem('enerCubix.locale.v1','zh-CN'));
 await installTransport(page);let allowed=false;
 await page.route('**/messages/changes?**',route=>allowed?route.fulfill({json:{ok:true,data:{items:[],total:0,offset:0,limit:30}}}):route.fulfill({status:403,json:{ok:false,error:{code:'PERMISSION',msg:'当前 FIN 会话无权访问此项目。'}}}));
 await openView(page,'messages');
 await page.getByRole('tab',{name:'重要变更',exact:true}).click();
 const section=page.locator('.change-messages');
 await expect(section.getByRole('alert')).toBeVisible();
 allowed=true;await section.getByRole('button',{name:'刷新记录',exact:true}).click();
 await expect(section.getByRole('alert')).toHaveCount(0);
 await expect(section).toContainText('暂无重要变更记录');
});
