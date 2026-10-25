import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US']){
 test.describe(locale,()=>{
  test.use({locale});
  test('renames, hides and restores the unassigned meter group without changing project records',async({page},testInfo)=>{
   const zh=locale==='zh-CN';
   const text={view:zh?'管理视图':'Management view',metering:zh?'计量':'Metering',organization:zh?'组织':'Organization',bucket:zh?'未配置上级表':'No parent meter',groupMenu:zh?'分组显示设置':'Group display settings',treeMenu:zh?'计量树显示设置':'Meter tree display settings',rename:zh?'重命名分组':'Rename group',hide:zh?'隐藏此层':'Hide this level',show:zh?'显示此层':'Show this level',reset:zh?'恢复默认名称':'Restore default name',dialog:zh?'分组改名':'Rename group',name:zh?'分组名称':'Group name',save:zh?/^保\s*存$/:'Save',cancel:zh?/^取\s*消$/:'Cancel'};
   const records:EnerCubixRecord[]=[
    {id:'electric',kind:'category',name:'电能',unit:'kWh'},
    {id:'master',kind:'totalMeter',name:'园区总表',categoryId:'electric',pointId:'point2'},
    {id:'orphan',kind:'meter',name:'独立分表',categoryId:'electric',pointId:'point1'},
    {id:'child',kind:'meter',name:'下级分表',categoryId:'electric',meterParentId:'orphan',pointId:'point3'}
   ];
   const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
   const state=await installTransport(page,{records:structuredClone(records)});
   await openView(page,'tree');
   const tree=page.locator('.meter-tree-panel');
   const switchView=async(name:string)=>page.getByRole('radiogroup',{name:text.view}).getByText(name,{exact:true}).click();
   const menuItem=async(menu:string,item:string)=>{await page.getByRole('button',{name:menu,exact:true}).click();await page.getByRole('menuitem',{name:item,exact:true}).click();await expect(page.locator('.ant-dropdown:visible')).toBeHidden();};
   await switchView(text.metering);
   await tree.locator('.ant-tree-title').filter({hasText:text.bucket}).click();
   await expect(page.getByRole('button',{name:text.groupMenu,exact:true})).toBeVisible();
   await menuItem(text.groupMenu,text.rename);
   const dialog=page.getByRole('dialog',{name:text.dialog,exact:true});
   await dialog.getByRole('textbox',{name:text.name,exact:true}).fill('   ');
   await expect(dialog.getByRole('button',{name:text.save,exact:true})).toBeDisabled();
   await dialog.getByRole('textbox',{name:text.name,exact:true}).fill('不应保存');
   await dialog.getByRole('button',{name:text.cancel,exact:true}).click();
   await expect(tree.getByText(text.bucket,{exact:true})).toBeVisible();
   await menuItem(text.groupMenu,text.rename);
   await dialog.getByRole('textbox',{name:text.name,exact:true}).fill('独立计量');
   await dialog.getByRole('button',{name:text.save,exact:true}).click();
   await expect(tree.getByText('独立计量',{exact:true})).toBeVisible();
   await expect(page.locator('.meter-context h3')).toHaveText('独立计量');
   await expect(page.locator('.ant-breadcrumb')).toContainText('独立计量');
   await page.reload();await switchView(text.metering);
   await expect(tree.getByText('独立计量',{exact:true})).toBeVisible();
   await tree.getByText('独立计量',{exact:true}).click();
   await menuItem(text.groupMenu,text.hide);
   await expect(tree.getByText('独立计量',{exact:true})).toHaveCount(0);
   await expect(tree.getByText('独立分表',{exact:true})).toBeVisible();
   await expect(page.locator('.meter-object-table').getByRole('button',{name:'独立分表',exact:true})).toBeVisible();
   await tree.getByText('独立分表',{exact:true}).click();
   await expect(page.locator('.meter-object-table').getByRole('button',{name:'下级分表',exact:true})).toBeVisible();
   await page.getByRole('dialog').getByRole('button',{name:'Close',exact:true}).click();
   await page.reload();await switchView(text.metering);
   await expect(tree.getByText('独立计量',{exact:true})).toHaveCount(0);
   await page.setViewportSize({width:390,height:844});
   await menuItem(text.treeMenu,text.show);
   await expect(tree.getByText('独立计量',{exact:true})).toBeVisible();
   await menuItem(text.groupMenu,text.reset);
   await expect(tree.getByText(text.bucket,{exact:true})).toBeVisible();
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
   await page.screenshot({path:testInfo.outputPath('meter-tree-display-mobile.png'),fullPage:true});
   await switchView(text.organization);
   await expect(page.getByRole('button',{name:text.treeMenu,exact:true})).toHaveCount(0);
   expect(state.records).toEqual(records);
   expect(state.requests.filter(request=>['records','tree/manage','records/delete'].includes(request.path))).toEqual([]);
   expect(errors).toEqual([]);
  });
 });
}
