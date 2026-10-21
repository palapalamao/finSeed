import {test,expect} from '@playwright/test';
import {installTransport,openView,testRecords} from './fixtures';
import type {FinPoint,SeedRecord} from '../../src/types';

const containers:SeedRecord[]=[
 {id:'site',kind:'space',name:'园区',nativeReadonly:true,nativeSourceKind:'site'},
 {id:'floor',kind:'space',name:'一层',parentId:'site',nativeReadonly:true,nativeSourceKind:'floor'},
 {id:'equip',kind:'space',name:'配电柜',parentId:'floor',nativeReadonly:true,nativeSourceKind:'equip'},
 {id:'nested',kind:'space',name:'嵌套电表',parentId:'equip',nativeReadonly:true,nativeSourceKind:'equip'},
];
const points:FinPoint[]=[
 {id:'point1',name:'园区 配电柜 累计电量',navName:'累计电量',unit:'kWh',his:true},
 {id:'point2',name:'园区 配电柜 分支电量',navName:'分支电量',unit:'kWh',his:true,hisStatus:'fault'},
 {id:'nohis',name:'实时功率',unit:'kW',his:false},
];
const leaves:SeedRecord[]=points.map(point=>({id:point.id,kind:'nativePoint',name:point.navName||point.name,parentId:point.id==='point2'?'nested':'equip',nativeReadonly:true,nativeSourceId:point.id,unit:point.unit,his:point.his}));

test('FIN admission selects historical leaves in the native tree and preserves choices across searches',async({page},testInfo)=>{
 const state=await installTransport(page,{records:[...testRecords(),...containers,...leaves],spaceSource:'fin'});
 await page.route('**/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:points,total:points.length,offset:0,limit:100}}}));
 await openView(page,'tree');await page.getByRole('button',{name:'从 FIN 点新增',exact:true}).click();
 const drawer=page.locator('.ant-drawer:visible'),tree=drawer.getByRole('tree',{name:'FIN 历史点树'});
 await expect(tree).toBeVisible();await expect(tree).toContainText('园区');await expect(tree).toContainText('一层');await expect(tree).toContainText('配电柜');await expect(tree).not.toContainText('实时功率');
 const node=(name:string)=>tree.locator('.ant-tree-treenode').filter({has:tree.getByText(name,{exact:true})});
 await node('累计电量').locator('.ant-tree-checkbox').click();await expect(drawer).toContainText('已选 1 个');await expect(drawer).toContainText('复用：测试分表');
 await drawer.getByPlaceholder('搜索 FIN 点名称或标识').fill('分支电量');await expect(tree).toContainText('嵌套电表');await expect(tree).not.toContainText('累计电量');await node('分支电量').locator('.ant-tree-checkbox').click();await expect(drawer).toContainText('已选 2 个');
 await drawer.getByPlaceholder('搜索 FIN 点名称或标识').clear();await expect(node('累计电量').locator('.ant-tree-checkbox')).toHaveClass(/checked/);await page.screenshot({path:testInfo.outputPath('fin-point-tree-desktop.png'),fullPage:true});
 await drawer.getByRole('button',{name:'下一步',exact:true}).click();await drawer.getByRole('button',{name:'下一步',exact:true}).click();await drawer.getByRole('button',{name:'确认加入 (2)',exact:true}).click();
 await expect.poll(()=>state.requests.filter(row=>row.path==='tree/manage'&&row.body.action==='save').length).toBe(1);
 const batch=state.requests.find(row=>row.body.action==='save')!.body.records as SeedRecord[];expect(batch.map(row=>row.pointId)).toEqual(['point1','point2']);
});

test('FIN space tree hides points without his and refresh removes newly ineligible leaves',async({page})=>{
 const state=await installTransport(page,{records:[...testRecords(),...containers,...leaves],spaceSource:'fin'});await openView(page,'tree');
 const tree=page.locator('.meter-tree-panel');await tree.getByRole('button',{name:'展开',exact:true}).click();await expect(tree).toContainText('累计电量');await expect(tree).not.toContainText('实时功率');
 state.records=state.records.map(row=>row.id==='point1'?{...row,his:false}:row);await page.getByRole('button',{name:'刷新项目',exact:true}).click();await expect(tree).not.toContainText('累计电量');expect(state.records.some(row=>row.id==='meter1')).toBe(true);
});

test('point tree loads later pages and remains usable on mobile',async({page},testInfo)=>{
 await installTransport(page);const offsets:number[]=[];
 const paged:FinPoint[]=Array.from({length:102},(_,i)=>({id:'paged-'+i,name:'分页点 '+i,his:true,unit:'kWh',siteId:'s',siteName:'测试站点',equipId:'e',equipName:'测试设备'}));paged[0].his=false;
 await page.route('**/v1/points?**',route=>{const offset=Number(new URL(route.request().url()).searchParams.get('offset'));offsets.push(offset);return route.fulfill({json:{ok:true,data:{items:paged.slice(offset,offset+100),total:paged.length,offset,limit:100}}});});
 await page.setViewportSize({width:390,height:844});await openView(page,'tree');await page.getByRole('button',{name:'从 FIN 点新增',exact:true}).click();const drawer=page.locator('.ant-drawer:visible');
 await drawer.getByPlaceholder('搜索 FIN 点名称或标识').fill('paged-101');const tree=drawer.getByRole('tree',{name:'FIN 历史点树'});await expect(tree).toContainText('分页点 101');expect(offsets).toEqual([0,100]);await expect(tree).toContainText('测试站点');await expect(tree).toContainText('测试设备');
 await tree.locator('.ant-tree-treenode').filter({has:tree.getByText('分页点 101',{exact:true})}).locator('.ant-tree-checkbox').click();await expect(drawer).toContainText('已选 1 个');await expect(drawer.getByRole('button',{name:'下一步',exact:true})).toBeEnabled();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);await page.screenshot({path:testInfo.outputPath('fin-point-tree-mobile.png'),fullPage:true});
 await drawer.getByPlaceholder('搜索 FIN 点名称或标识').fill('paged-0');await expect(drawer).toContainText('没有匹配的历史点');await expect(drawer).toContainText('已选 1 个');
});
