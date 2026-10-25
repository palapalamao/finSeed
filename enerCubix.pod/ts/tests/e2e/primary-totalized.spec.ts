import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`primary counter ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('explains the marker and writes only when the binding is saved',async({page})=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  const records:EnerCubixRecord[]=[{id:'site',kind:'space',name:'园区',nativeSourceKind:'site',nativeSourceId:'site',nativeReadonly:true},{id:'cat',kind:'category',name:'电力',unit:'kWh'},{id:'equip',mod:'m1',kind:'meter',name:'总电表',pointId:'p',categoryId:'cat',unit:'kWh',nativeEquip:true,nativeSpaceId:'equip',nativeTreeParentId:'site'}];
  const state=await installTransport(page,{records,spaceSource:'fin',storageModel:'nativeEquip'});await openView(page,'tree');
  await page.locator('.meter-tree-panel').getByRole('button',{name:zh?'全部对象':'All objects',exact:true}).click();
  const edit=page.getByRole('button',{name:zh?'编辑总电表':'Edit总电表',exact:true});await edit.click();
  const drawer=page.locator('.ant-drawer-open');
  await expect(drawer.getByText(zh?'保存时会为主能耗点添加累计读数标签（hisTotalized），原始历史值保持不变。':'Saving adds the cumulative-reading marker (hisTotalized) to the primary energy point and preserves raw history values.',{exact:false})).toBeVisible();
  expect(state.requests.filter(r=>r.path==='records')).toHaveLength(0);
  await drawer.locator('.ant-drawer-close').click();await expect(drawer).toHaveCount(0);
  expect(state.requests.filter(r=>r.path==='records')).toHaveLength(0);
  await edit.click();await page.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.requests.filter(r=>r.path==='records').length).toBe(1);
  expect(state.requests.find(r=>r.path==='records')!.body.record).toMatchObject({id:'equip',pointId:'p',kind:'meter'});
 });
});
