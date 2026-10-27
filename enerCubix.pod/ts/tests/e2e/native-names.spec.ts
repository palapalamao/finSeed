import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`FIN device names ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('follows FIN unless an alias is explicitly enabled, and can switch back',async({page},testInfo)=>{
  const zh=locale==='zh-CN';
  if(mobile)await page.setViewportSize({width:390,height:844});
  const meter:EnerCubixRecord={id:'equip',mod:'m1',kind:'totalMeter',name:'总电表1F空调用电',nativeName:'总电表1F空调用电',nativeEquip:true,useAlias:false,pointId:'p1',categoryId:'cat',unit:'kWh',nativeTreeParentId:'site'};
  const state=await installTransport(page,{records:[{id:'site',kind:'space',name:'园区',nativeSourceKind:'site'},{id:'cat',kind:'category',name:'电',unit:'kWh'},meter],spaceSource:'fin',storageModel:'nativeEquip'});
  await openView(page,'tree');
  await page.locator('.meter-tree-panel').getByRole('button',{name:zh?'全部对象':'All objects',exact:true}).click();
  const edit=async(name:string)=>page.getByRole('button',{name:(zh?'编辑':'Edit')+name,exact:true}).click();
  await edit(meter.name);
  const drawer=page.locator('.ant-drawer-open');
  const alias=drawer.getByRole('switch',{name:zh?'使用自定义别名':'Use a custom alias',exact:true});
  const name=drawer.getByRole('textbox',{name:zh?/^(?:\*\s*)?名称$/:/^(?:\*\s*)?Name$/});
  await expect(alias).not.toBeChecked();await expect(name).toBeDisabled();await expect(name).toHaveValue(meter.name);
  await expect(drawer.getByText(zh?'默认跟随 FIN 设备名称；在 FIN 中改名后刷新即可同步。':'Follow the FIN equipment name by default. Refresh after renaming it in FIN.',{exact:true})).toBeVisible();
  await page.screenshot({path:testInfo.outputPath('follow-fin-name.png'),fullPage:true});
  await alias.check();await name.fill('自定义总表');
  await drawer.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
  expect(state.requests.find(row=>row.path==='records')!.body.record).toMatchObject({id:'equip',name:'自定义总表',useAlias:true,pointId:'p1'});
  await page.reload();await expect(page.locator('.content-frame')).toBeVisible();
  await page.locator('.meter-tree-panel').getByRole('button',{name:zh?'全部对象':'All objects',exact:true}).click();
  await edit('自定义总表');
  await alias.uncheck();await expect(name).toBeDisabled();await expect(name).toHaveValue(meter.name);
  await drawer.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(2);
  expect(state.requests.filter(row=>row.path==='records')[1].body.record).toMatchObject({id:'equip',name:meter.name,useAlias:false,pointId:'p1'});
 });
});

for(const locale of ['zh-CN','en-US'])test.describe(`FIN name enrollment ${locale}`,()=>{
 test.use({locale});
 test('enrollment only sends a custom alias after enabling its switch',async({page})=>{
  const zh=locale==='zh-CN';
  const state=await installTransport(page,{records:[{id:'site',kind:'space',name:'园区',nativeSourceKind:'site'},{id:'equip',mod:'m1',kind:'space',name:'FIN设备',parentId:'site',nativeSourceId:'equip',nativeSourceKind:'equip',nativeReadonly:true},{id:'cat',kind:'category',name:'电',unit:'kWh'}],spaceSource:'fin',storageModel:'nativeEquip'});
  await page.route('**/api/testproject/ext/enerCubix/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:[{id:'p1',equipId:'equip',name:'电量',his:true,unit:'kWh'}],total:1}}}));
  await openView(page,'tree');await page.getByRole('button',{name:zh?'纳入 FIN 设备':'Enroll FIN equipment',exact:true}).click();
  await page.locator('.ant-drawer .ant-table-tbody tr').filter({hasText:'FIN设备'}).getByRole('checkbox').check();
  await page.getByRole('button',{name:zh?'下一步':'Next',exact:true}).click();
  const input=page.getByRole('textbox',{name:zh?'FIN设备别名':'FIN设备Alias',exact:true});
  await expect(input).toBeDisabled();
  await page.getByRole('switch',{name:'FIN设备'+(zh?'使用自定义别名':'Use a custom alias'),exact:true}).check();
  await input.fill('我的表计');
  await page.getByRole('combobox',{name:zh?'纳入设备能源类型':'Energy type for enrolled equipment'}).click();await page.getByTitle('电 · kWh',{exact:true}).click();
  await expect(page.locator('.ant-drawer-open').getByTitle('电量 · kWh',{exact:true})).toBeVisible();
  await page.getByRole('button',{name:zh?'下一步':'Next',exact:true}).click();
  await page.getByRole('button',{name:zh?'确认纳入 (1)':'Confirm enrollment (1)',exact:true}).click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='tree/manage'&&row.body.action==='save').length).toBe(1);
  const saved=(state.requests.find(row=>row.path==='tree/manage'&&row.body.action==='save')!.body.records as EnerCubixRecord[])[0];
  expect(saved).toMatchObject({id:'equip',name:'我的表计',useAlias:true,pointId:'p1'});
 });
});
