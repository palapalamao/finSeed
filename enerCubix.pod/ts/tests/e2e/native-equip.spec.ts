import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';
for(const scenario of [{locale:'zh-CN',mobile:false},{locale:'en-US',mobile:false},{locale:'zh-CN',mobile:true}])test.describe('new native main meter '+scenario.locale+' '+(scenario.mobile?'mobile':'desktop'),()=>{
 test.use({locale:scenario.locale});
 test('creates equipment and an energy point without a formula',async({page})=>{
  const zh=scenario.locale==='zh-CN';
  if(scenario.mobile)await page.setViewportSize({width:390,height:844});
  const state=await installTransport(page,{records:[...records,{id:'floor',mod:'f1',kind:'space',name:'一楼',parentId:'site',nativeReadonly:true,nativeSourceKind:'floor',nativeSourceId:'floor'}],spaceSource:'fin',storageModel:'nativeEquip'});
  await openView(page,'tree');
  await expect(page.getByRole('button',{name:zh?'新增总表':'Add main meter',exact:true})).toBeVisible({timeout:2000});
  await page.getByRole('button',{name:zh?'新增总表':'Add main meter',exact:true}).click();
  const drawer=page.locator('.ant-drawer-open');
  await drawer.getByRole('textbox',{name:zh?'名称':'Name'}).fill('EC总表');
  await drawer.getByRole('combobox',{name:zh?'FIN 所属站点':'FIN site'}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('园区',{exact:true}).click();
  await drawer.getByRole('combobox',{name:zh?'FIN 楼层 / 设备目录':'FIN floor / equipment folder'}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('一楼',{exact:true}).click();
  await drawer.getByRole('combobox',{name:zh?'能源类型':'Energy type'}).click();await page.locator('.ant-select-dropdown:visible').getByTitle(zh?'电力 (能源类型)':'电力 (Energy type)',{exact:true}).click();
  await expect(drawer.getByRole('combobox',{name:zh?'计算公式':'Calculation formula',exact:true})).toHaveCount(0);
  await expect(drawer.getByRole('switch',{name:zh?'按分表计算当前值':'Calculate current value from submeters',exact:true})).toBeChecked();
  await drawer.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
  const saved=state.requests.find(row=>row.path==='records')!.body.record as EnerCubixRecord;
  expect(saved).toMatchObject({kind:'totalMeter',name:'EC总表',createNative:true,siteId:'site',floorId:'floor',categoryId:'cat',autoSum:true});
  expect(saved).not.toHaveProperty('createVirtual');expect(saved).not.toHaveProperty('expressionId');expect(saved).not.toHaveProperty('pointId');
 });
});
const records:EnerCubixRecord[]=[
 {id:'site',mod:'s1',kind:'space',name:'园区',nativeReadonly:true,nativeSourceKind:'site',nativeSourceId:'site'},
 {id:'equip',mod:'e1',kind:'space',name:'待纳入设备',parentId:'site',nativeReadonly:true,nativeSourceKind:'equip',nativeSourceId:'equip'},
 {id:'cat',mod:'c1',kind:'category',name:'电力',unit:'kWh'},
];
for(const mobile of [false,true])test(`native equipment enrollment chooses its own primary point on ${mobile?'mobile':'desktop'}`,async({page},testInfo)=>{
 if(mobile)await page.setViewportSize({width:390,height:844});
 const state=await installTransport(page,{records:structuredClone(records),spaceSource:'fin'});
 await page.route('**/api/testproject/ext/enerCubix/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:[{id:'p1',equipId:'equip',name:'第一电量',navName:'第一电量',his:true,unit:'kWh'},{id:'p2',equipId:'equip',name:'第二电量',navName:'第二电量',his:true,unit:'kWh'},{id:'foreign',equipId:'another',name:'外设备点',his:true,unit:'kWh'},{id:'nohis',equipId:'equip',name:'未启用历史',his:false,unit:'kWh'},{id:'water',equipId:'equip',name:'水量',his:true,unit:'m³'}],total:5}}}));
 await openView(page,'tree');await page.getByRole('button',{name:'纳入 FIN 设备',exact:true}).click();
 await expect(page.getByRole('button',{name:'设备模型迁移',exact:true})).toHaveCount(0);
 await page.locator('.ant-drawer .ant-table-tbody tr').filter({hasText:'待纳入设备'}).getByRole('checkbox').check();
 await page.getByRole('button',{name:'下一步',exact:true}).click();
 await page.getByRole('combobox',{name:'纳入设备能源类型'}).click();await page.getByTitle('电力 · kWh',{exact:true}).click();
 await expect(page.getByRole('button',{name:'下一步',exact:true})).toBeDisabled();
 await page.getByRole('combobox',{name:'待纳入设备主能耗点'}).click();
 await expect(page.getByTitle('外设备点 · kWh',{exact:true})).toHaveCount(0);await expect(page.getByTitle('未启用历史 · kWh',{exact:true})).toHaveCount(0);await expect(page.getByTitle('水量 · m³',{exact:true})).toHaveCount(0);
 await page.getByTitle('第二电量 · kWh',{exact:true}).click();await page.getByRole('button',{name:'下一步',exact:true}).click();
 await page.screenshot({path:testInfo.outputPath('native-enroll.png'),fullPage:true});
 await page.getByRole('button',{name:'确认纳入 (1)',exact:true}).click();
 await expect.poll(()=>state.requests.filter(row=>row.path==='tree/manage'&&row.body.action==='save').length).toBe(1);
 const saved=(state.requests.find(row=>row.path==='tree/manage'&&row.body.action==='save')!.body.records as EnerCubixRecord[])[0];
 expect(saved).toMatchObject({id:'equip',mod:'e1',pointId:'p2',categoryId:'cat',nativeEquip:true});expect(saved).not.toHaveProperty('siteRef');expect(saved).not.toHaveProperty('parentId');
});
test('read-only FIN user cannot enroll equipment',async({page})=>{await installTransport(page,{records,spaceSource:'fin',storageModel:'nativeEquip',canWrite:false});await openView(page,'tree');await expect(page.getByRole('button',{name:'纳入 FIN 设备',exact:true})).toBeDisabled();});

for(const locale of ['zh-CN','en-US'])test.describe(`native equipment properties in ${locale}`,()=>{
 test.use({locale});
 test('edits the same raw equipment and retains its primary point',async({page})=>{
  const zh=locale==='zh-CN';
  const meter:EnerCubixRecord={id:'equip',mod:'e1',kind:'meter',name:'总电表',pointId:'p1',categoryId:'cat',unit:'kWh',nativeEquip:true,nativeSpaceId:'equip',nativeTreeParentId:'site'};
  const state=await installTransport(page,{records:[...records.filter(row=>row.id!=='equip'),meter],spaceSource:'fin',storageModel:'nativeEquip'});
  await openView(page,'tree');await page.locator('.meter-tree-panel').getByRole('button',{name:zh?'全部对象':'All objects',exact:true}).click();await page.getByRole('button',{name:(zh?'编辑':'Edit')+'总电表',exact:true}).click();
  const toggle=page.getByRole('switch',{name:zh?'按分表计算当前值':'Calculate current value from submeters',exact:true});
  await expect(toggle).toBeVisible();await toggle.check();
  await page.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
  expect(state.requests.find(row=>row.path==='records')!.body.record).toMatchObject({id:'equip',mod:'e1',nativeEquip:true,pointId:'p1',autoSum:true});
  expect(state.requests.some(row=>row.path.startsWith('migration'))).toBe(false);
 });
});
