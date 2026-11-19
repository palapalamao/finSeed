import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';

for(const language of ['zh-CN','en-US'])test.describe(language,()=>{
 test.use({locale:language});
 for(const mobile of [false,true])test(`continuous alarm retains hourly detail ${mobile?'mobile':'desktop'}`,async({page})=>{
  if(mobile)await page.setViewportSize({width:390,height:844});
  const zh=language==='zh-CN';
  const state=await installTransport(page,{alarms:[{id:'alarm1',mod:'m1',kind:'alarm',name:'原始设备名',nodeId:'meter1',categoryId:'cat1',ts:'2026-10-23T13:00:00+08:00',episodeStartTs:'2026-10-23T13:00:00+08:00',lastTs:'2026-10-23T14:00:00+08:00',hourCount:2,latestValue:15,value:19,limit:7,unit:'kWh',state:'open',nativeAlarmId:'alarm1_offNormal',nativeActive:true,hours:[{ts:'2026-10-23T13:00:00+08:00',value:19,limit:7,unit:'kWh',quality:'ok'},{ts:'2026-10-23T14:00:00+08:00',value:15,limit:7,unit:'kWh',quality:'ok',priorAckBy:'原确认人',priorAckNote:'原始备注'}]}]});
  await openView(page,'alarms');
  await expect(page.getByRole('columnheader',{name:zh?'确认状态':'Acknowledgement',exact:true})).toBeVisible();
  await expect(page.getByText(zh?'持续超限':'Exceedance ongoing',{exact:true})).toBeVisible();
  await page.locator('.ant-table-row-expand-icon').first().click();
  await expect(page.locator('.ant-table-expanded-row')).toContainText('原始备注');
  await expect(page.locator('.ant-table-expanded-row')).toContainText('2026-10-23T14:00:00+08:00');
  await page.screenshot({path:`../../out/alarm-episodes-${language}-${mobile?'mobile':'desktop'}.png`,fullPage:true});
  state.alarms[0].recoveredAt='2026-10-23T16:00:00+08:00';state.alarms[0].nativeActive=false;
  await page.getByRole('button',{name:zh?/刷新报警/:/Refresh alarms/}).click();
  await expect(page.getByText(zh?'已恢复':'Recovered',{exact:true})).toBeVisible();
  await expect(page.getByRole('button',{name:zh?'确认报警':'Acknowledge alarm',exact:true})).toBeEnabled();
 });
});
