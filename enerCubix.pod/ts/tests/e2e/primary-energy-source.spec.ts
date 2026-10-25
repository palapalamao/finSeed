import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US'])test.describe(locale,()=>{
 test.use({locale});
 test('identifies the saved calculation point and moves the marker only after saving a new source',async({page},testInfo)=>{
  const zh=locale==='zh-CN';
  const text={expand:zh?'展开':'Expand',badge:zh?'能耗计算源':'Energy calculation source',details:zh?'表计详情':'Meter details',edit:zh?'编辑表计属性':'Edit meter properties',main:zh?'主能耗点':'Main energy point',save:zh?'保存配置':'Save configuration',unbound:zh?'未配置能耗计算源':'Energy calculation source not configured',unused:zh?'未选作能耗计算源':'Not selected as an energy calculation source'};
  const records:EnerCubixRecord[]=[
   {id:'category',kind:'category',name:'电能',unit:'kWh'},
   {id:'site',kind:'space',name:'测试站点',nativeReadonly:true,nativeSourceKind:'site'},
   {id:'floor',kind:'space',name:'一层',parentId:'site',nativeReadonly:true,nativeSourceKind:'floor'},
   {id:'meter',mod:'m1',kind:'meter',name:'一号电表',parentId:'floor',nativeEquip:true,nativeSpaceId:'meter',nativeTreeParentId:'floor',nativeDis:'站点 一号电表',pointId:'point-a',categoryId:'category',includeInTotals:true},
   {id:'point-a',kind:'nativePoint',name:'电量 A',parentId:'meter',nativeReadonly:true,nativeSourceId:'point-a',his:true,unit:'kWh'},
   {id:'point-b',kind:'nativePoint',name:'电量 B',parentId:'meter',nativeReadonly:true,nativeSourceId:'point-b',his:true,unit:'kWh'},
   {id:'new-meter',kind:'space',name:'未纳入电表',parentId:'floor',nativeReadonly:true,nativeSourceKind:'equip'},
   {id:'candidate',kind:'nativePoint',name:'候选电量',parentId:'new-meter',nativeReadonly:true,nativeSourceId:'candidate',his:true,unit:'kWh'}
  ];
  const state=await installTransport(page,{records,storageModel:'nativeEquip',spaceSource:'fin'});
  await page.route('**/api/testproject/ext/enerCubix/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:[{id:'point-a',name:'站点 一号电表 电量 A',navName:'电量 A',equipId:'meter',unit:'kWh',his:true},{id:'point-b',name:'站点 一号电表 电量 B',navName:'电量 B',equipId:'meter',unit:'kWh',his:true}],total:2,offset:0,limit:500}}}));
  await openView(page,'tree');
  const tree=page.locator('.meter-tree-panel');
  await tree.getByRole('button',{name:text.expand,exact:true}).click();
  const node=(name:string)=>tree.locator('.ant-tree-treenode').filter({has:page.locator('.ant-tree-title').getByText(name,{exact:true})});
  await node('一号电表').locator('.ant-tree-switcher').click();
  await expect(node('电量 A')).toContainText(text.badge);
  await expect(node('电量 B')).not.toContainText(text.badge);
  await expect(node('候选电量')).not.toContainText(text.badge);
  await node('一号电表').locator('.ant-tree-title').getByText('一号电表',{exact:true}).click();
  let detail=page.getByRole('dialog',{name:text.details,exact:true});
  await expect(detail.locator('.ant-descriptions-item').filter({hasText:text.main})).toContainText('电量 A');
  await expect(detail.getByText(text.badge,{exact:true})).toBeVisible();
  await detail.getByRole('button',{name:'Close',exact:true}).click();
  const rows=page.locator('.meter-object-table tbody tr');
  await expect(rows.filter({hasText:'电量 A'}).getByText(text.badge,{exact:true})).toBeVisible();
  await expect(rows.filter({hasText:'电量 B'}).getByText(text.badge,{exact:true})).toHaveCount(0);
  await node('电量 A').locator('.ant-tree-title').getByText('电量 A',{exact:true}).click();
  detail=page.getByRole('dialog',{name:text.details,exact:true});
  await expect(detail).toContainText(text.badge);
  await detail.getByRole('button',{name:'Close',exact:true}).click();
  await node('电量 B').locator('.ant-tree-title').getByText('电量 B',{exact:true}).click();
  await expect(detail).toContainText(text.unused);
  await expect(detail.getByText(text.badge,{exact:true})).toHaveCount(0);
  await detail.getByRole('button',{name:'Close',exact:true}).click();
  await node('未纳入电表').locator('.ant-tree-title').getByText('未纳入电表',{exact:true}).click();
  await expect(detail).toContainText(text.unbound);
  await detail.getByRole('button',{name:'Close',exact:true}).click();
  await node('一号电表').locator('.ant-tree-title').getByText('一号电表',{exact:true}).click();
  await detail.getByRole('button',{name:text.edit,exact:true}).click();
  const editor=page.locator('.ant-drawer-open');
  await expect(editor).toContainText(zh?'保存后，所选点的历史数据将作为本设备的能耗计算源。':'After saving, the selected point’s history will be used to calculate this equipment’s energy consumption.');
  await editor.getByRole('combobox',{name:text.main,exact:true}).press('ArrowDown');
  await page.locator('.ant-select-dropdown:visible').getByText(/电量 B/).click();
  await expect(node('电量 A')).toContainText(text.badge);
  await expect(node('电量 B')).not.toContainText(text.badge);
  await editor.getByRole('button',{name:text.save,exact:true}).click();
  await expect.poll(()=>state.records.find(row=>row.id==='meter')?.pointId).toBe('point-b');
  await expect(node('电量 B')).toContainText(text.badge);
  await expect(node('电量 A')).not.toContainText(text.badge);
  await expect(editor).toBeHidden();
  const finalDetail=page.getByRole('dialog',{name:text.details,exact:true});if(await finalDetail.isVisible())await finalDetail.getByRole('button',{name:'Close',exact:true}).click();
  await page.screenshot({path:testInfo.outputPath('primary-energy-source-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});
  await node('电量 B').scrollIntoViewIfNeeded();await page.evaluate(()=>window.scrollTo(0,0));
  await expect(node('电量 B').getByText(text.badge,{exact:true})).toBeVisible();
  const panelBox=(await tree.boundingBox())!,badgeBox=(await node('电量 B').getByText(text.badge,{exact:true}).boundingBox())!;
  expect(badgeBox.y+badgeBox.height).toBeLessThanOrEqual(panelBox.y+panelBox.height);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('primary-energy-source-mobile.png'),fullPage:true});
 });
});
