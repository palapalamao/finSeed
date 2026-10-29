import {test,expect} from '@playwright/test';
import {installTransport} from './fixtures';
import {readFileSync} from 'node:fs';
const uiVersion=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;

for(const en of [false,true])test(`stale frontend shows its real version and offers reload in ${en?'English':'Chinese'}`,async({page})=>{
 await page.addInitScript(value=>localStorage.setItem('enerCubix.locale.v1',value),en?'en-US':'zh-CN');
 const state=await installTransport(page);
 await page.route('**/api/testproject/ext/enerCubix/v1/catalog',route=>route.fulfill({json:{ok:true,data:{version:'0.12.99',project:'testproject',storageModel:'nativeEquip',user:{name:'Test',canWrite:true},records:state.records}}}));
 await page.goto('/#/energyFlow?project=testproject');
 await expect(page.locator('.nav-version').last()).toHaveText('v'+uiVersion);
 const notice=page.getByRole('alert').filter({hasText:en?'The current interface version':'当前界面版本'});
 await expect(notice).toContainText(uiVersion);await expect(notice).toContainText('0.12.99');
 await page.route('**/api/testproject/ext/enerCubix/',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><h1>Updated application entry</h1>'}));
 await notice.getByRole('button',{name:en?'Load updated interface':'加载新版界面',exact:true}).click();
 await expect(page).toHaveURL(/\/api\/testproject\/ext\/enerCubix\/$/);
 await expect(page.getByRole('heading',{name:'Updated application entry'})).toBeVisible();
});
