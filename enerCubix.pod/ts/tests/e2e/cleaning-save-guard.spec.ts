import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US'])test.describe(locale,()=>{
 test.use({locale});
 test('keeps the editor open with persistent named cleaning blockers',async({page},info)=>{
  const zh=locale==='zh-CN';
  const records:EnerCubixRecord[]=[
   {id:'cat',kind:'category',name:'电能',unit:'kWh'},
   {id:'profile',kind:'cleaningProfile',name:'默认方案',mode:'drop',parameters:{defNull:true}},
   {id:'main',mod:'m1',kind:'totalMeter',name:'园区总表',pointId:'point2',categoryId:'cat',unit:'kWh',autoSum:true,cleaningEnabled:true,cleaningProfileId:'profile'},
   {id:'branch',kind:'meter',name:'分电表 3',pointId:'point1',categoryId:'cat',meterParentId:'main'}
  ];
  const state=await installTransport(page,{records});let saves=0;
  await page.route('**/api/testproject/ext/enerCubix/v1/records',route=>{saves++;return route.fulfill({status:400,json:{ok:false,error:{code:'CLEANING_SOURCES',msg:'虚拟总表“园区总表”无法保存清洗配置，请先处理以下问题：\n“分电表 3”：尚未启用清洗或未选择清洗方案'}}});});
  await openView(page,'tree');
  await page.getByRole('radiogroup',{name:zh?'管理视图':'Management view'}).getByText(zh?'计量':'Metering',{exact:true}).click();
  const tree=page.locator('.meter-tree-panel');await tree.getByRole('button',{name:zh?'展开':'Expand',exact:true}).click();
  await tree.locator('.ant-tree-title').getByText('园区总表',{exact:true}).click();
  await page.getByRole('dialog').getByRole('button',{name:zh?'编辑表计属性':'Edit meter properties',exact:true}).click();
  const editor=page.locator('.ant-drawer-open');
  await editor.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  const alert=editor.locator('.ant-alert-error');
  await expect(alert).toContainText('分电表 3');
  await expect(alert).toContainText(zh?'尚未启用清洗或未选择清洗方案':'Cleaning is not enabled or no cleaning profile is selected.');
  await expect(editor.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true})).toBeEnabled();
  await page.screenshot({path:info.outputPath('cleaning-save-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});await alert.scrollIntoViewIfNeeded();
  await expect(alert).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:info.outputPath('cleaning-save-mobile.png'),fullPage:true});
  // FIN's CSRF transport retries a 400 once; every attempt must remain rejected.
  expect(saves).toBeGreaterThan(0);expect(state.records).toEqual(records);
 });
});
