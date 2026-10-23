import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {SeedRecord} from '../../src/types';
const records:SeedRecord[]=[
 {id:'site',mod:'s1',kind:'space',name:'园区',nativeReadonly:true,nativeSourceKind:'site',nativeSourceId:'site'},
 {id:'equip',mod:'e1',kind:'space',name:'待纳入设备',parentId:'site',nativeReadonly:true,nativeSourceKind:'equip',nativeSourceId:'equip'},
 {id:'cat',mod:'c1',kind:'category',name:'电力',unit:'kWh'},
];
for(const mobile of [false,true])test(`native equipment enrollment chooses its own primary point on ${mobile?'mobile':'desktop'}`,async({page},testInfo)=>{
 if(mobile)await page.setViewportSize({width:390,height:844});
 const state=await installTransport(page,{records:structuredClone(records),spaceSource:'fin',storageModel:'nativeEquip'});
 await page.route('**/api/testproject/ext/enerCubix/v1/points?**',route=>route.fulfill({json:{ok:true,data:{items:[{id:'p1',equipId:'equip',name:'第一电量',navName:'第一电量',his:true,unit:'kWh'},{id:'p2',equipId:'equip',name:'第二电量',navName:'第二电量',his:true,unit:'kWh'},{id:'foreign',equipId:'another',name:'外设备点',his:true,unit:'kWh'},{id:'nohis',equipId:'equip',name:'未启用历史',his:false,unit:'kWh'},{id:'water',equipId:'equip',name:'水量',his:true,unit:'m³'}],total:5}}}));
 await openView(page,'tree');await page.getByRole('button',{name:'纳入 FIN 设备',exact:true}).click();
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
 const saved=(state.requests.find(row=>row.path==='tree/manage'&&row.body.action==='save')!.body.records as SeedRecord[])[0];
 expect(saved).toMatchObject({id:'equip',mod:'e1',pointId:'p2',categoryId:'cat',nativeEquip:true});expect(saved).not.toHaveProperty('siteRef');expect(saved).not.toHaveProperty('parentId');
});
test('read-only FIN user cannot enroll equipment',async({page})=>{await installTransport(page,{records,spaceSource:'fin',storageModel:'nativeEquip',canWrite:false});await openView(page,'tree');await expect(page.getByRole('button',{name:'纳入 FIN 设备',exact:true})).toBeDisabled();});
