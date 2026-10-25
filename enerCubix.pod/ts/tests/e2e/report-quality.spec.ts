import {test,expect} from '@playwright/test';
import {installTransport,openView,testRecords} from './fixtures';

for(const [language,mobile]of [['zh-CN',false],['en-US',false],['zh-CN',true]] as const)test(`report explains missing readings in ${language}${mobile?' on mobile':''}`,async({page})=>{
 await page.setViewportSize(mobile?{width:390,height:844}:{width:1440,height:1000});
 await page.addInitScript(locale=>localStorage.setItem('enerCubix.locale.v1',locale),language);
 await page.clock.setFixedTime(new Date('2026-10-24T02:10:57+08:00'));
 const request={kind:'profile',nodeIds:['master1'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-24T03:00:00+08:00',period:'hour',metric:'energy',perArea:false};
 await installTransport(page,{records:[...testRecords(),{id:'quality-template',kind:'template',name:'缺测提示测试',request}]});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const points=[0,1,2].map(hour=>({ts:`2026-10-24T0${hour}:00:00+08:00`,value:null,quality:'missing',sourceIds:['point2']}));
  await route.fulfill({json:{ok:true,data:{kind:'profile',from:request.from,to:request.to,period:'hour',series:[{id:'master1',nodeId:'master1',name:'测试总表',unit:'kWh',points}],rows:points,summary:{totals:[{id:'master1',name:'测试总表',value:null,quality:'missing'}]},warnings:['测试总表 : missing','测试总表: missing']}}});
 });
 await page.route('**/api/testproject/ext/enerCubix/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:[{id:'point2',name:'电能',his:true,hisStart:'2026-10-24T01:45:00+08:00',hisEnd:'2026-10-24T02:10:00+08:00'}],total:1}}}));
 await openView(page,'profile');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('缺测提示测试',{exact:true}).click();
 await page.getByRole('button',{name:language==='zh-CN'?/查\s*询/:/^Query$/}).click();
 const warning=page.locator('.report-warning');await expect(warning).toHaveCount(1);await expect(warning).toContainText('测试总表');
 await expect(warning).toContainText(language==='zh-CN'?'缺少起始读数':'Missing start reading');
 await expect(warning).toContainText(language==='zh-CN'?'时段尚未结束':'Interval not finished');
 await expect(warning).toContainText('2026-10-24 01:45');await expect(warning).toContainText('2026-10-24 03:00');
 await page.locator('.report-details summary').click();await expect(page.locator('.report-details')).not.toContainText(/\bmissing\b/);
 await page.locator('.quality-details summary').click();await expect(page.locator('.quality-details')).toContainText(language==='zh-CN'?'时段尚未结束':'Interval not finished');
 await expect(page.locator('.report-surface').getByText('missing',{exact:true})).toHaveCount(0);
 await expect(page.locator('.metric-readout strong').first()).toContainText('—');
 if(mobile)expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await page.screenshot({path:`../../out/report-quality-${language}${mobile?'-mobile':''}.png`,fullPage:true});
});
