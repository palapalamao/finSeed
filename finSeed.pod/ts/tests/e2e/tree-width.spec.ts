import {test,expect,type Locator,type Page} from '@playwright/test';
import {checkNode,installTransport,openView,query} from './fixtures';

async function width(panel:Locator){return Math.round((await panel.boundingBox())!.width);}
async function resize(page:Page,handle:Locator,delta:number){const box=(await handle.boundingBox())!;await page.mouse.move(box.x+box.width/2,box.y+60);await page.mouse.down();await page.mouse.move(box.x+box.width/2+delta,box.y+60,{steps:10});await page.mouse.up();}

test('analysis tree width follows dragging and survives refresh and report navigation',async({page})=>{
 await installTransport(page);await openView(page,'profile');const panel=page.locator('.object-panel'),handle=page.getByRole('separator',{name:'分析对象树宽度'});const initial=await width(panel);
 await expect(handle).toBeVisible();await checkNode(page);await query(page);const chartWidth=await width(page.locator('.report-chart'));await resize(page,handle,110);await expect.poll(()=>width(panel)).toBe(initial+110);await expect.poll(()=>width(page.locator('.report-chart canvas'))).toBe(chartWidth-110);
 await page.reload();await expect.poll(()=>width(panel)).toBe(initial+110);await openView(page,'ranking');await expect.poll(()=>width(panel)).toBe(initial+110);
 await handle.focus();await page.keyboard.press('ArrowLeft');await expect.poll(()=>width(panel)).toBe(initial+94);await page.reload();await expect.poll(()=>width(panel)).toBe(initial+94);
});

test('meter tree keeps its own width and adapts to mobile without losing the desktop preference',async({page})=>{
 await installTransport(page);await openView(page,'tree');const panel=page.locator('.meter-tree-panel'),handle=page.getByRole('separator',{name:'计量对象树宽度'});const initial=await width(panel);
 await expect(handle).toBeVisible();await resize(page,handle,80);await expect.poll(()=>width(panel)).toBe(initial+80);await page.reload();await expect.poll(()=>width(panel)).toBe(initial+80);
 await openView(page,'profile');await expect.poll(()=>width(page.locator('.object-panel'))).toBe(228);await openView(page,'tree');await expect.poll(()=>width(panel)).toBe(initial+80);
 await page.setViewportSize({width:390,height:844});await expect(handle).toBeHidden();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 await page.setViewportSize({width:1440,height:1000});await expect.poll(()=>width(panel)).toBe(initial+80);
});

test('tree width is bounded and unavailable local storage does not prevent resizing',async({page})=>{
 await page.addInitScript(()=>{Storage.prototype.getItem=()=>{throw new Error('storage disabled');};Storage.prototype.setItem=()=>{throw new Error('storage disabled');};});
 await installTransport(page);await openView(page,'profile');const panel=page.locator('.object-panel'),handle=page.getByRole('separator',{name:'分析对象树宽度'});
 await handle.focus();await page.keyboard.press('Home');await expect.poll(()=>width(panel)).toBe(180);await page.keyboard.press('End');
 expect(await width(page.locator('.analysis-workspace'))).toBeGreaterThanOrEqual(480);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);await expect(page.getByRole('button',{name:/查\s*询/})).toBeVisible();
});
