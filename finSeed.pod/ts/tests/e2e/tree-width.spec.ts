import {test,expect,type Locator,type Page} from '@playwright/test';
import {installTransport,openView,openObjects,closeObjects} from './fixtures';
async function width(panel:Locator){return Math.round((await panel.boundingBox())!.width);}
async function resize(page:Page,handle:Locator,delta:number){const box=(await handle.boundingBox())!;await page.mouse.move(box.x+box.width/2,box.y+60);await page.mouse.down();await page.mouse.move(box.x+box.width/2+delta,box.y+60,{steps:10});await page.mouse.up();}

test('object chooser uses an overlay and leaves the full analysis width available',async({page})=>{
 await installTransport(page);await openView(page,'profile');const workspace=page.locator('.analysis-workspace');
 const initial=await width(workspace);await expect(page.locator('.object-panel:visible')).toHaveCount(0);
 await openObjects(page);await expect(page.locator('.object-panel')).toBeVisible();expect(await width(workspace)).toBe(initial);
 await closeObjects(page);await page.setViewportSize({width:390,height:844});await openObjects(page);
 expect(await width(page.getByRole('dialog',{name:'选择分析对象'}))).toBeLessThanOrEqual(390);
 await closeObjects(page);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

test('meter tree keeps its own width and adapts to mobile without losing the desktop preference',async({page})=>{
 await installTransport(page);await openView(page,'tree');const panel=page.locator('.meter-tree-panel'),handle=page.getByRole('separator',{name:'计量对象树宽度'});const initial=await width(panel);
 await expect(handle).toBeVisible();await resize(page,handle,80);await expect.poll(()=>width(panel)).toBe(initial+80);await page.reload();await expect.poll(()=>width(panel)).toBe(initial+80);
 await openView(page,'profile');await expect(page.locator('.object-panel:visible')).toHaveCount(0);await openView(page,'tree');await expect.poll(()=>width(panel)).toBe(initial+80);
 await page.setViewportSize({width:390,height:844});await expect(handle).toBeHidden();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.setViewportSize({width:1440,height:1000});await expect.poll(()=>width(panel)).toBe(initial+80);
});

test('meter tree can still be resized when browser preference storage is unavailable',async({page})=>{
 await page.addInitScript(()=>{Storage.prototype.getItem=()=>{throw new Error('storage disabled');};Storage.prototype.setItem=()=>{throw new Error('storage disabled');};});
 await installTransport(page);await openView(page,'tree');const panel=page.locator('.meter-tree-panel'),handle=page.getByRole('separator',{name:'计量对象树宽度'});
 await handle.focus();await page.keyboard.press('Home');await expect.poll(()=>width(panel)).toBe(180);await page.keyboard.press('End');
 expect(await width(page.locator('.meter-main'))).toBeGreaterThanOrEqual(320);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
