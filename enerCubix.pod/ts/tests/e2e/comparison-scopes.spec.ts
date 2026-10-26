import {test,expect} from '@playwright/test';
import {installTransport,openView,checkNode} from './fixtures';
import type {ComparisonScope,EnerCubixRecord,ReportRequest} from '../../src/types';

const request:ReportRequest={kind:'leak',dimension:'space',nodeIds:['master'],from:'2026-10-01T00:00:00+08:00',to:'2026-10-02T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
const scopes:ComparisonScope[]=[{nodeId:'master',categoryId:'electric',availableMembers:[{nodeId:'a',name:'Branch A',unit:'kWh'},{nodeId:'b',name:'Branch B',unit:'kWh'}],defaultMemberIds:['a','b'],quality:'ok'}];
const records:EnerCubixRecord[]=[{id:'site',kind:'space',name:'Site'},{id:'electric',kind:'category',name:'Electric',unit:'kWh'},{id:'master',kind:'totalMeter',name:'Master',nativeEquip:true,pointId:'p0',spaceId:'site',categoryId:'electric'},{id:'a',kind:'meter',name:'Branch A',nativeEquip:true,pointId:'pa',spaceId:'site',meterParentId:'master',categoryId:'electric',includeInTotals:false},{id:'b',kind:'meter',name:'Branch B',nativeEquip:true,pointId:'pb',spaceId:'site',meterParentId:'master',categoryId:'electric',includeInTotals:false},{id:'old-template',kind:'template',name:'Old automatic template',request},{id:'new-template',kind:'template',name:'Saved explicit none',request:{...request,comparisonBasis:'physicalBoundary',comparisonMembers:{master:[]}}}];

for(const language of ['zh-CN','en-US'])test(`readonly physical comparison distinguishes defaults, none and subset in ${language}`,async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 await page.addInitScript(value=>localStorage.setItem('enerCubix.locale.v1',value),language);
 const state=await installTransport(page,{records:structuredClone(records),canWrite:false});
 const scopeCalls:string[]=[];
 await page.route('**/comparison-scopes?*',async route=>{scopeCalls.push(new URL(route.request().url()).searchParams.get('nodeIds')!);expect(route.request().method()).toBe('GET');await route.fulfill({json:{ok:true,data:{scopes}}});});
 await openView(page,'leak');await checkNode(page,'Master');
 const panel=page.locator('.comparison-members');await expect(panel).toBeVisible();await expect(panel).toContainText('Branch A');await expect(panel).toContainText('Branch B');
 const query=page.getByRole('button',{name:language==='zh-CN'?/查\s*询/:'Query',exact:true});
 await query.click();await expect.poll(()=>state.requests.filter(item=>item.path==='report').length).toBe(1);
 expect(state.requests.filter(item=>item.path==='report').at(-1)!.body).toMatchObject({comparisonBasis:'physicalBoundary'});
 expect(state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonMembers).toEqual({});
 await panel.getByRole('button',{name:language==='zh-CN'?'不选分表':'Select no submeters',exact:true}).click();await query.click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonMembers).toEqual({master:[]});
 const select=panel.getByRole('combobox');await select.click();await page.locator('.ant-select-dropdown:visible').getByText('Branch A',{exact:true}).click();await page.keyboard.press('Escape');await query.click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonMembers).toEqual({master:['a']});
 await panel.getByRole('button',{name:language==='zh-CN'?'恢复默认全部':'Restore default members',exact:true}).click();await query.click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonMembers).toEqual({});
 await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('Saved explicit none',{exact:true}).click();
 await expect(panel).toContainText(language==='zh-CN'?'已明确不选分表':'No submeters explicitly selected');await query.click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonMembers).toEqual({master:[]});
 await page.getByRole('button',{name:language==='zh-CN'?'重置条件':'Reset conditions',exact:true}).click();await checkNode(page,'Master');await query.click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonMembers).toEqual({});
 for(const width of [1440,390]){await page.setViewportSize({width,height:960});await expect(panel).toBeVisible();await expect(panel).toContainText('Branch A');await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await panel.screenshot({path:testInfo.outputPath(`comparison-${language}-${width}.png`)});}
 await page.setViewportSize({width:1440,height:1000});
 await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('Old automatic template',{exact:true}).click();await expect(panel).toHaveCount(0);await query.click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='report').at(-1)!.body.comparisonBasis).toBeUndefined();
 expect(scopeCalls).toContain('master');expect(state.requests.filter(item=>item.path==='records'||item.path==='tree/manage')).toEqual([]);expect(errors).toEqual([]);
});

test('saving a new template preserves physical basis and an explicit empty selection',async({page})=>{
 const state=await installTransport(page,{records:structuredClone(records)});
 await page.route('**/comparison-scopes?*',route=>route.fulfill({json:{ok:true,data:{scopes}}}));
 await openView(page,'leak');await checkNode(page,'Master');
 await page.locator('.comparison-members').getByRole('button',{name:'不选分表',exact:true}).click();
 await page.getByRole('button',{name:'存为模板',exact:true}).click();
 await page.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect.poll(()=>state.requests.filter(item=>item.path==='records').length).toBe(1);
 expect((state.requests.find(item=>item.path==='records')!.body.record as EnerCubixRecord).request).toMatchObject({nodeIds:['master'],comparisonBasis:'physicalBoundary',comparisonMembers:{master:[]}});
 expect(state.records.find(row=>row.id==='a')!.includeInTotals).toBe(false);
});

test('ignores a stale scope response after the selected master changes',async({page})=>{
 const extra:EnerCubixRecord[]=[{id:'other',kind:'totalMeter',name:'Alternate',spaceId:'site',categoryId:'electric',expressionId:'virtual'}];
 await installTransport(page,{records:[...structuredClone(records),...extra],canWrite:false});
 let release:()=>void=()=>{},complete:()=>void=()=>{};const held=new Promise<void>(resolve=>release=resolve),finished=new Promise<void>(resolve=>complete=resolve);let first=false;
 await page.route('**/comparison-scopes?*',async route=>{
  const ids=new URL(route.request().url()).searchParams.get('nodeIds');
  if(ids==='master'&&!first){first=true;await held;await route.fulfill({json:{ok:true,data:{scopes}}}).catch(()=>{});complete();return;}
  await route.fulfill({json:{ok:true,data:{scopes:[{nodeId:'other',categoryId:'electric',availableMembers:[{nodeId:'b',name:'Other resolved branch'}],defaultMemberIds:['b'],quality:'ok'}]}}});
 });
 await openView(page,'leak');await checkNode(page,'Master');await expect.poll(()=>first).toBe(true);
 await checkNode(page,'Alternate');await checkNode(page,'Master');
 await expect(page.locator('.comparison-members')).toContainText('Other resolved branch');release();await finished;
 await expect(page.locator('.comparison-members')).not.toContainText('Branch A');
 await expect(page.locator('.comparison-members .comparison-member-field')).toHaveCount(1);
});
