import {test,expect} from '@playwright/test';
import {installTransport,openView,openObjects,closeObjects,testRecords} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

function records():EnerCubixRecord[]{return [
 ...testRecords().map(row=>row.id==='master1'?{...row,spaceId:'building',organizationId:'company'}:row.id==='meter1'?{...row,meterParentId:'middle',spaceId:'room',organizationId:'team'}:row),
 {id:'site',kind:'space',name:'园区'}, {id:'building',kind:'space',name:'楼栋',parentId:'site'},
 {id:'room',kind:'space',name:'房间',parentId:'building'},
 {id:'middle',kind:'totalMeter',name:'中间总表',meterParentId:'master1',categoryId:'cat1',pointId:'middle-point'},
 {id:'company',kind:'organization',name:'公司'}, {id:'department',kind:'organization',name:'部门',parentId:'company'},
 {id:'team',kind:'organization',name:'小组',parentId:'department'}
];}
for(const locale of ['zh-CN','en-US'] as const)for(const mobile of [false,true]){
 test(`utility metering selection and shallow object trees ${locale} ${mobile?'mobile':'desktop'}`,async({page})=>{
  await page.setViewportSize(mobile?{width:390,height:844}:{width:1440,height:1000});
  await page.addInitScript(value=>localStorage.setItem('enerCubix.locale.v1',value),locale);
  const state=await installTransport(page,{records:records()});await openView(page,'utility');
  const metering=page.getByRole('radio',{name:locale==='zh-CN'?'计量':'Metering',exact:true});
  await expect(metering).toBeEnabled();await page.locator('label').filter({has:metering}).click();await openObjects(page);
  const titles=page.locator('.object-panel .ant-tree-title');
  await expect(titles.getByText('测试总表',{exact:true})).toBeVisible();
  await expect(titles.getByText('中间总表',{exact:true})).not.toBeVisible();
  const master=page.locator('.object-panel .ant-tree-treenode').filter({hasText:'测试总表'});
  await expect(master.locator('.ant-tree-checkbox')).not.toHaveClass(/disabled/);await master.locator('.ant-tree-checkbox').click();
  await closeObjects(page);await page.getByRole('button',{name:locale==='zh-CN'?/查\s*询/:'Query',exact:true}).click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='report').at(-1)?.body.dimension).toBe('metering');
  expect(state.requests.filter(row=>row.path==='report').at(-1)?.body.nodeIds).toEqual(['master1']);
  await openObjects(page);await master.locator('.ant-tree-switcher').click();await expect(titles.getByText('中间总表',{exact:true})).toBeVisible();
  await closeObjects(page);await openObjects(page);await expect(titles.getByText('中间总表',{exact:true})).not.toBeVisible();await closeObjects(page);
  for(const [label,visible,hidden]of locale==='zh-CN'?[['空间','楼栋','房间'],['组织','部门','小组']]:[['Space','楼栋','房间'],['Organization','部门','小组']]){
   await page.locator('label').filter({has:page.getByRole('radio',{name:label,exact:true})}).click();await openObjects(page);
   await expect(titles.getByText(visible,{exact:true})).toBeVisible();await expect(titles.getByText(hidden,{exact:true})).not.toBeVisible();await closeObjects(page);
  }
 });
}
