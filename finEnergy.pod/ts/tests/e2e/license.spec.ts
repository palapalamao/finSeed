import {expect,test} from '@playwright/test';
import type {LicenseStatus} from '../../src/license';
import {installTransport,openView} from './fixtures';
const active:LicenseStatus={source:'fin',status:'active',feature:'fin energy',canManageFinLicense:true,hostId:'HID-EXAMPLE-FOR-NATIVE-FIN-LICENSE'};
for(const [language,label,native] of [['zh-CN','授权管理','FIN 原生授权'],['en-US','License management','Native FIN license']]){
 test(`native FIN license is read-only in ${language}`,async({page})=>{
  const state=await installTransport(page,{userLocale:language});
  await page.route('**/v1/license/status',route=>route.fulfill({json:{ok:true,data:active}}));
  await openView(page,'license');await expect(page.getByRole('heading',{name:label,exact:true})).toBeVisible();
  await expect(page.getByText(native,{exact:true})).toBeVisible();await expect(page.getByText(active.hostId!,{exact:true})).toBeVisible();
  await expect(page.getByText('fin energy',{exact:true})).toBeVisible();
  await expect(page.locator('input[type=file]')).toHaveCount(0);await expect(page.getByRole('button',{name:/添加授权|删除授权|Add license|Delete license|Export license request/})).toHaveCount(0);
  expect(state.requests.some(request=>request.path==='license/import'||request.path==='license/delete')).toBe(false);
 });
}
test('an unlicensed English mobile page explains native recovery without overflow',async({page})=>{
 await page.setViewportSize({width:390,height:844});await installTransport(page,{userLocale:'en-US',canWrite:true});
 await page.route('**/v1/license/status',route=>route.fulfill({json:{ok:true,data:{...active,status:'missingFeature',canManageFinLicense:false,hostId:undefined,reason:'nativeLicenseRequired'}}}));
 await openView(page,'license');await expect(page.getByText('FIN energy feature license required',{exact:true})).toBeVisible();
 await expect(page.getByText(/Ask a FIN license administrator/)).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
