import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';

for(const locale of ['zh-CN','en-US'])test.describe(locale,()=>{
 test.use({locale});
 for(const mobile of [false,true])test('metering assets are configured inside settings on '+(mobile?'mobile':'desktop'),async({page},testInfo)=>{
  const zh=locale==='zh-CN';
  const labels={navigation:zh?'主导航':'Main navigation',open:zh?'打开导航':'Open navigation',settings:zh?'设置':'Settings',assets:zh?'计量资产':'Metering assets',heading:zh?'计量对象管理':'Metering objects',categories:zh?'能源分类与分项':'Energy types and end uses'};
  if(mobile)await page.setViewportSize({width:390,height:844});
  const state=await installTransport(page);await openView(page,'profile');
  if(mobile)await page.getByRole('button',{name:labels.open,exact:true}).click();
  const navigation=mobile?page.getByRole('dialog',{name:labels.navigation}).getByRole('navigation',{name:labels.navigation}):page.getByRole('navigation',{name:labels.navigation});
  await expect(navigation.getByRole('button',{name:labels.assets,exact:true})).toHaveCount(0);
  await navigation.getByRole('button',{name:labels.settings,exact:true}).click();
  if(mobile)await expect(page.getByRole('dialog',{name:labels.navigation})).toBeHidden();
  await expect(page.getByRole('tab',{name:labels.assets,exact:true})).toHaveAttribute('aria-selected','true');
  await expect(page.getByRole('heading',{name:labels.heading,exact:true})).toBeVisible();
  await expect(page).toHaveURL(/#\/tree\?project=testproject$/);
  await page.getByRole('tab',{name:labels.categories,exact:true}).click();
  await expect(page.getByRole('heading',{name:labels.categories,exact:true})).toBeVisible();
  await page.goto('/#/tree?project=testproject');
  await expect(page.getByRole('tab',{name:labels.assets,exact:true})).toHaveAttribute('aria-selected','true');
  await expect(page.locator('.primary-navigation button[aria-current="page"]')).toHaveText(labels.settings);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  expect(state.requests.some(request=>request.path==='records'||request.path==='migration')).toBe(false);
  await page.screenshot({path:testInfo.outputPath('settings-'+locale+'-'+(mobile?'mobile':'desktop')+'.png'),fullPage:true});
 });
});
