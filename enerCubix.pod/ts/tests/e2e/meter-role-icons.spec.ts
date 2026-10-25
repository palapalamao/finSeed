import {test,expect} from '@playwright/test';
import {installTransport,openView,openObjects} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US'])test.describe(locale,()=>{
 test.use({locale});
 test('distinguishes physical, virtual and unconfirmed total sources at every tree level',async({page},testInfo)=>{
  const zh=locale==='zh-CN';const main=zh?'物理总表':'pTotal Meter',virtual=zh?'虚拟总表':'vTotal Meter',sub=zh?'分表':'Submeter';
  const records:EnerCubixRecord[]=[
   {id:'electric',kind:'category',name:'电能',unit:'kWh'},
   {id:'main',kind:'totalMeter',name:'进线计量',categoryId:'electric',pointId:'p',meterOrigin:{type:'physical',reason:'connector',protocol:'modbus',connectorId:'conn',pointId:'p'}},
   {id:'branch',kind:'meter',name:'支路计量',categoryId:'electric',meterParentId:'main'},
   {id:'leaf',kind:'meter',name:'末端计量',categoryId:'electric',meterParentId:'branch'},
   {id:'nested',kind:'totalMeter',name:'楼层汇总',categoryId:'electric',meterParentId:'main',autoSum:true},
   {id:'unknown',kind:'totalMeter',name:'待核实设备',categoryId:'electric'},
   {id:'independent',kind:'meter',name:'独立计量',categoryId:'electric'}
  ];
  const state=await installTransport(page,{records,canWrite:false});await openView(page,'tree');
  await page.getByRole('radiogroup',{name:zh?'管理视图':'Management view'}).getByText(zh?'计量':'Metering',{exact:true}).click();
  const tree=page.locator('.meter-tree-panel');await tree.getByRole('button',{name:zh?'展开':'Expand',exact:true}).click();
  const node=(name:string)=>tree.locator('.ant-tree-treenode').filter({has:page.locator('.ant-tree-title').getByText(name,{exact:true})});
  await expect(node('进线计量').getByText(main,{exact:true})).toBeVisible();
  await expect(node('楼层汇总').getByText(virtual,{exact:true})).toBeVisible();
  await expect(node('待核实设备').getByText(zh?'来源待确认':'Source unconfirmed',{exact:true})).toBeVisible();
  for(const name of ['支路计量','末端计量','独立计量']){await expect(node(name).getByText(sub,{exact:true})).toBeVisible();await expect(node(name).getByText(main,{exact:true})).toHaveCount(0);}
  const mainIcon=await node('进线计量').locator('.ant-tree-iconEle svg').getAttribute('data-icon');
  const virtualIcon=await node('楼层汇总').locator('.ant-tree-iconEle svg').getAttribute('data-icon');
  expect(mainIcon).toBe('dashboard');expect(virtualIcon).toBe('calculator');
  await node('进线计量').locator('.ant-tree-node-content-wrapper').click();
  await expect(page.locator('.meter-properties')).toContainText('modbus');
  await page.screenshot({path:testInfo.outputPath('meter-role-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:testInfo.outputPath('meter-source-mobile-detail.png'),fullPage:true});
  await page.locator('.ant-drawer-close').click();await node('楼层汇总').scrollIntoViewIfNeeded();await page.evaluate(()=>window.scrollTo(0,0));
  await expect(node('楼层汇总').getByText(virtual,{exact:true})).toBeVisible();
  const panelBox=(await tree.boundingBox())!,badgeBox=(await node('楼层汇总').getByText(virtual,{exact:true}).boundingBox())!;
  expect(badgeBox.y+badgeBox.height).toBeLessThanOrEqual(panelBox.y+panelBox.height);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('meter-role-mobile.png'),fullPage:true});
  expect(state.records).toEqual(records);expect(state.requests.some(row=>['records','tree/manage'].includes(row.path))).toBe(false);
  await openView(page,'profile');await openObjects(page);
  await expect(page.locator('.object-panel').getByText(main,{exact:true})).toBeVisible();
  await expect(page.locator('.object-panel').getByText(virtual,{exact:true})).toBeVisible();
 });
});
