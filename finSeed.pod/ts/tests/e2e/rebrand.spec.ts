import {test,expect} from '@playwright/test';
import {installTransport,openView,testRecords} from './fixtures';

test('horizontal workspace preserves query filters while changing independent analysis views',async({page},testInfo)=>{
 const records=[...testRecords().map(row=>row.id==='meter1'?{...row,spaceId:'floor',organizationId:'department'}:row),{id:'floor',kind:'space' as const,name:'示范楼层'},{id:'department',kind:'organization' as const,name:'示范部门'}];
 const state=await installTransport(page,{records});await openView(page,'profile');
 await expect(page.getByRole('navigation',{name:'主导航'})).toBeVisible();
 await expect(page).toHaveTitle('能源魔方 · 多维能源分析平台');
 await expect(page.locator('.brand-wordmark')).toContainText('能源魔方');
 await expect(page.locator('.object-panel:visible')).toHaveCount(0);
 await page.getByRole('button',{name:/^选择对象/}).click();
 const drawer=page.getByRole('dialog',{name:'选择分析对象'});
 await drawer.locator('.ant-tree-treenode').filter({hasText:'测试分表'}).locator('.ant-tree-checkbox').click();
 await drawer.getByRole('button',{name:'完成选择'}).click();
 await page.getByRole('button',{name:/^查\s*询$/}).click();
 await expect(page.getByRole('button',{name:'导出当前报表'})).toBeVisible();
 const first=state.requests.filter(row=>row.path==='report').at(-1)!.body;
 expect(first.dimension).toBe('space');expect(first.nodeIds).toEqual(['meter1']);
 await page.getByRole('radiogroup',{name:'分析视角'}).getByText('组织',{exact:true}).click();
 await expect(page.locator('.scope-selection')).toContainText('0');
 await expect(page.getByRole('button',{name:'导出当前报表'})).toHaveCount(0);
 await page.getByRole('button',{name:/^选择对象/}).click();
 await drawer.locator('.ant-tree-treenode').filter({hasText:'示范部门'}).locator('.ant-tree-checkbox').click();
 await drawer.getByRole('button',{name:'完成选择'}).click();
 await page.getByRole('button',{name:/^查\s*询$/}).click();
 await expect.poll(()=>state.requests.filter(row=>row.path==='report').at(-1)?.body.dimension).toBe('organization');
 const next=state.requests.filter(row=>row.path==='report').at(-1)!.body;
 expect(next.nodeIds).toEqual(['department']);for(const key of ['from','to','period','metric'])expect(next[key]).toEqual(first[key]);
 await page.screenshot({path:testInfo.outputPath('enercubix-analysis-desktop.png'),fullPage:true});
 await page.getByRole('tab',{name:'构成与排名',exact:true}).click();
 await page.getByRole('tab',{name:'能耗占比',exact:true}).click();
 await expect(page).toHaveURL(/#\/proportion\?project=testproject$/);
 await page.getByRole('navigation',{name:'主导航'}).getByRole('button',{name:'设置',exact:true}).click();
 await expect(page.getByRole('tab',{name:'计量资产',exact:true})).toHaveAttribute('aria-selected','true');
 await expect(page.getByRole('heading',{name:'计量对象管理',exact:true})).toBeVisible();
});

test('mobile workspace keeps navigation, language and object selection accessible',async({page},testInfo)=>{
 await page.setViewportSize({width:390,height:844});await installTransport(page);await openView(page,'profile');
 await expect(page.locator('.brand-wordmark')).toContainText('能源魔方');
 await page.getByRole('button',{name:'打开导航',exact:true}).click();
 await page.getByRole('dialog',{name:'主导航'}).getByRole('button',{name:'异常中心',exact:true}).click();
 await expect(page.getByRole('heading',{name:'能耗报警',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'打开导航',exact:true}).click();
 await page.getByRole('dialog',{name:'主导航'}).getByRole('button',{name:'分析工作台',exact:true}).click();
 await expect(page.getByRole('radiogroup',{name:'分析视角'})).toBeVisible();
 await page.getByRole('button',{name:/^选择对象/}).click();
 await expect(page.getByRole('dialog',{name:'选择分析对象'})).toBeVisible();
 await page.getByRole('button',{name:'完成选择'}).click();
 await expect(page.getByRole('dialog',{name:'选择分析对象'})).toBeHidden();
 await expect(page.getByRole('button',{name:'切换语言',exact:true})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
 await page.screenshot({path:testInfo.outputPath('enercubix-analysis-mobile.png'),fullPage:true});
});

test('read-only users can open legacy templates from the template center without migrating data',async({page})=>{
 const state=await installTransport(page,{canWrite:false});await openView(page,'templates');
 await page.getByRole('button',{name:'打开分析',exact:true}).click();
 await expect(page.getByRole('heading',{name:'能耗概况',exact:true})).toBeVisible();
 await expect(page.getByText('模板已锁定对象选择',{exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:'另存为模板',exact:true})).toBeDisabled();
 await page.getByRole('button',{name:'查询',exact:true}).click();
 await expect(page.getByRole('button',{name:'导出当前报表'})).toBeVisible();
 const request=state.requests.filter(row=>row.path==='report').at(-1)!.body;
 expect(request.dimension).toBe('legacy');expect(request.nodeIds).toEqual(['meter1']);
 expect(state.requests.filter(row=>row.path==='records'||row.path==='migration')).toHaveLength(0);
});
