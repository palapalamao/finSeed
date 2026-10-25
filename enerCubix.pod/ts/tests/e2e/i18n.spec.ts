import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,checkNode} from './fixtures';

for(const language of ['zh-CN','zh-TW','en-US','de-DE']){
 test.describe(language,()=>{
  test.use({locale:language});
  const chinese=language.startsWith('zh');
  test('automatically localizes navigation, query and report while retaining project names',async({page})=>{
   const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
   const state=await installTransport(page);
   await openView(page,'profile');
   await expect(page.locator('html')).toHaveAttribute('lang',chinese?'zh-CN':'en-US');
   await expect(page).toHaveTitle(chinese?'能源魔方 · 多维能源分析平台':'EnerCubix · Multidimensional Energy Analytics');
   await expect(page.getByRole('heading',{name:chinese?'能耗概况':'Consumption profile',exact:true})).toBeVisible();
   await expect(page.getByRole('navigation').getByRole('button',{name:chinese?'总览':'Overview',exact:true})).toBeVisible();
   await expect(page.getByRole('combobox',{name:chinese?'汇总间隔':'Aggregation interval',exact:true})).toBeVisible();
   await checkNode(page);
   await page.getByRole('button',{name:chinese?/查\s*询/:/Query$/}).click();
   await expect(page.getByRole('button',{name:chinese?'导出当前报表':'Export current report'})).toBeVisible();
   await expect(page.locator('.report-chart canvas').first()).toBeVisible();
   await expect(page.locator('.report-surface')).toContainText('测试分表');
   if(!chinese)expect(await page.locator('.primary-navigation .nav-active').evaluate(element=>element.scrollWidth<=element.clientWidth)).toBe(true);
   expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.nodeIds).toEqual(['meter1']);
   expect(errors).toEqual([]);
   if(language==='zh-CN'||language==='en-US')await page.screenshot({path:`../../out/i18n-${language}.png`,fullPage:true});
  });
 });
}

test.describe('English controls and exports',()=>{
 test.use({locale:'en-US'});
 test('keeps English navigation usable on a small screen',async({page})=>{
  await page.setViewportSize({width:390,height:844});
  await installTransport(page);await openView(page,'profile');
  await page.getByRole('button',{name:'Open navigation',exact:true}).click();
  await page.getByRole('dialog').getByRole('button',{name:'Overview',exact:true}).click();
  await expect(page.locator('.workspace-title h2')).toHaveText('Energy overview');
 });
 test('opens all analysis and configuration workspaces in English',async({page})=>{
  const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
  await installTransport(page);
  for(const [view,title] of Object.entries({dashboard:'Energy overview',ranking:'Consumption ranking',proportion:'Consumption share',utility:'End-use consumption',daily:'Daily load',comparison:'Comparison analysis',primary:'Primary energy analysis',cop:'COP analysis',leak:'Leak analysis',forecast:'Energy forecast',trend:'Point trends',tree:'Metering objects',tariffs:'Tariffs',calendars:'Calendars and time bands',expressions:'Calculation formulas',copConfig:'COP configuration',bindings:'Reference point bindings',templates:'Report templates',tasks:'Calculation and alarm tasks',settings:'Overview settings'})){
   await openView(page,view);
   await expect(page.locator('.workspace-title h2')).toHaveText(title);
  }
  expect(errors).toEqual([]);
 });
 test('localizes date picker, forms, validation and alarms',async({page})=>{
  await installTransport(page);await openView(page,'profile');
  await page.getByPlaceholder('Start date',{exact:true}).click();
  await expect(page.locator('.ant-picker-dropdown:visible').getByRole('button',{name:'Choose a month',exact:true})).toBeVisible();
  await page.keyboard.press('Escape');
  await openView(page,'categories');
  await page.getByRole('button',{name:/Add Energy type$/}).click();
  await expect(page.getByRole('dialog')).toContainText('Add Energy type');
  await page.getByRole('button',{name:'Save configuration',exact:true}).click();
  await expect(page.getByText('Enter a name',{exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Cancel',exact:true}).click();
  await openView(page,'alarms');
  await expect(page.getByRole('heading',{name:'Energy alarms',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Acknowledge alarm',exact:true}).click();
  await expect(page.getByPlaceholder('Acknowledgement note (optional)')).toBeVisible();
  await expect(page.getByRole('dialog').getByRole('button',{name:'Cancel',exact:true})).toBeVisible();
 });
 test('exports English headers with unmodified project object names',async({page})=>{
  await installTransport(page);await openView(page,'profile');await checkNode(page);
  await page.getByRole('button',{name:/Query$/}).click();
  await page.getByRole('button',{name:'Export current report'}).click();
  const downloadPromise=page.waitForEvent('download');
  await page.getByRole('menuitem',{name:'Excel workbook (.xlsx)'}).click();
  const download=await downloadPromise;
  expect(download.suggestedFilename()).toContain('Consumption profile');
  const zip=await JSZip.loadAsync(await readFile((await download.path())!));
  const workbook=await zip.file('xl/workbook.xml')!.async('string');
  const shared=await zip.file('xl/sharedStrings.xml')!.async('string');
  expect(workbook).toContain('Report information');expect(workbook).toContain('Statistics');
  expect(shared).toContain('Source points');expect(shared).toContain('测试分表');
  expect(shared).not.toContain('统计明细');
 });
 test('localizes a known service error and handles a missing project',async({page})=>{
  await installTransport(page,{status:401});await page.goto('/#/dashboard?project=testproject');
  await expect(page.getByText('Your FIN session has expired. Sign in to FIN again.',{exact:true})).toBeVisible();
  await page.goto('/');
  await expect(page.getByText('No FIN project specified',{exact:true})).toBeVisible();
  await expect(page.getByRole('navigation').getByRole('button',{name:'Overview',exact:true})).toBeVisible();
 });
});

test.describe('manual language selection',()=>{
 test.use({locale:'zh-CN'});
 test('switches both ways, persists across reloads and restores automatic language',async({page})=>{
  await installTransport(page);await openView(page,'profile');
  await page.getByRole('button',{name:'切换语言',exact:true}).click();
  await page.getByRole('menuitem',{name:'English',exact:true}).click();
  await expect(page.locator('html')).toHaveAttribute('lang','en-US');
  await expect(page.getByRole('heading',{name:'Consumption profile',exact:true})).toBeVisible();
  await expect(page).toHaveURL(/#\/profile\?project=testproject$/);
  await page.reload();
  await expect(page.getByRole('heading',{name:'Consumption profile',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Switch language',exact:true}).click();
  await page.getByRole('menuitem',{name:'中文',exact:true}).click();
  await expect(page.getByRole('heading',{name:'能耗概况',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'切换语言',exact:true}).click();
  await page.getByRole('menuitem',{name:'English',exact:true}).click();
  await expect(page.getByRole('heading',{name:'Consumption profile',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Switch language',exact:true}).click();
  await page.getByRole('menuitem',{name:'Use system language',exact:true}).click();
  await expect(page.locator('html')).toHaveAttribute('lang','zh-CN');
  await expect(page.getByRole('heading',{name:'能耗概况',exact:true})).toBeVisible();
 });
 test('can switch on mobile even when browser storage is blocked',async({page})=>{
  await page.setViewportSize({width:390,height:844});
  await page.addInitScript(()=>{Object.defineProperty(window,'localStorage',{configurable:true,get:()=>{throw new Error('blocked');}});});
  await installTransport(page);await openView(page,'profile');
  await page.getByRole('button',{name:'切换语言',exact:true}).click();
  await page.getByRole('menuitem',{name:'English',exact:true}).click();
  await expect(page.getByRole('heading',{name:'Consumption profile',exact:true})).toBeVisible();
  await expect(page).toHaveURL(/enerCubixLang=en-US/);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  await page.getByRole('button',{name:'Switch language',exact:true}).click();
  await page.getByRole('menuitem',{name:'Use system language',exact:true}).click();
  await expect(page.getByRole('heading',{name:'能耗概况',exact:true})).toBeVisible();
 });
});
