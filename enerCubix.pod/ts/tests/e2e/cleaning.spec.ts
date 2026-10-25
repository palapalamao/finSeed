import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';
import type {EnerCubixRecord} from '../../src/types';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`cleaning profiles ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('creates default profiles and edits explicit zero replacement without leaking mode flags',async({page})=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  const state=await installTransport(page);await openView(page,'otherSettings');
  await page.getByRole('tab',{name:zh?'数据清洗方案':'Cleaning profiles',exact:true}).click();
  await page.getByRole('button',{name:zh?'新增清洗方案':'Add cleaning profile',exact:true}).click();
  const drawer=page.locator('.ant-drawer-open');
  await expect(drawer.getByText(zh?'新查询按当前规则清洗尚未归档的原始读数；已发布用量和旧报告快照保留原版本。调整已发布历史须指定时间范围修正；预览不会改写历史。':'New queries clean raw readings that have no published consumption using the current rules. Published consumption and old report snapshots retain their original versions. Correcting published history requires a specified time range; preview does not rewrite history.',{exact:true})).toBeVisible();
  await drawer.getByRole('textbox',{name:zh?'方案名称':'Profile name',exact:true}).fill('工况 A');
  await expect(drawer.getByRole('spinbutton',{name:zh?'最小增量（deltaMin）':'Minimum delta (deltaMin)',exact:true})).toHaveValue('0');
  await expect(drawer.getByRole('switch',{name:zh?'启用最大增量（deltaMax）':'Enable Maximum delta (deltaMax)',exact:true})).not.toBeChecked();
  await drawer.getByRole('button',{name:zh?'保存清洗方案':'Save cleaning profile',exact:true}).click();
  await expect.poll(()=>state.records.filter(row=>row.kind==='cleaningProfile').length).toBe(1);
  expect(state.records.find(row=>row.kind==='cleaningProfile')).toMatchObject({name:'工况 A',mode:'drop',parameters:{deltaMin:0,timeMax:'1h',defNull:true}});
  await page.getByRole('row').filter({hasText:'工况 A'}).getByRole('button',{name:zh?/编\s*辑/:'Edit',exact:true}).click();
  await drawer.getByRole('combobox',{name:zh?'清洗模式':'Cleaning mode',exact:true}).press('Enter');
  await page.locator('.ant-select-dropdown:visible').getByTitle(zh?'替代异常':'Replace anomalies',{exact:true}).click();
  await drawer.getByRole('spinbutton',{name:zh?'异常替代值（defVal）':'Anomaly replacement (defVal)',exact:true}).fill('0');
  await drawer.getByRole('textbox',{name:zh?'异常替代值（defVal）单位':'Anomaly replacement (defVal) unit',exact:true}).fill('kWh');
  await drawer.getByRole('button',{name:zh?'保存清洗方案':'Save cleaning profile',exact:true}).click();
  await expect.poll(()=>state.records.find(row=>row.kind==='cleaningProfile')?.mode).toBe('replace');
  expect(state.records.find(row=>row.kind==='cleaningProfile')?.parameters).toEqual({deltaMin:0,timeMax:'1h',defVal:{type:'number',value:0,unit:'kWh'}});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 });
 test('read-only users can preview saved raw and cleaned history within a bounded range',async({page})=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  const state=await installTransport(page,{canWrite:false});const previews:Record<string,unknown>[]=[];
  await page.route('**/v1/cleaning/preview',route=>{previews.push(route.request().postDataJSON());return route.fulfill({json:{ok:true,data:{
   from:'2026-10-20T00:00:00+08:00',to:'2026-10-21T00:00:00+08:00',unit:'kWh',
   raw:[{ts:'2026-10-20T00:00:00+08:00',value:100,valueType:'number'},{ts:'2026-10-20T00:10:00+08:00',value:112,valueType:'number'},{ts:'2026-10-20T00:20:00+08:00',value:107,valueType:'number'},{ts:'2026-10-20T00:30:00+08:00',value:107,valueType:'number'}],
   cleaned:[{ts:'2026-10-20T00:00:00+08:00',value:12,valueType:'number'},{ts:'2026-10-20T00:10:00+08:00',value:null,valueType:'na'},{ts:'2026-10-20T00:20:00+08:00',value:0,valueType:'number'}],
   summary:{inputCount:4,filteredCount:0,substitutedCount:1,naCount:1,coverage:2/3},details:[{ts:'2026-10-20T00:10:00+08:00',intervalStart:'2026-10-20T00:10:00+08:00',intervalEnd:'2026-10-20T00:20:00+08:00',reason:'deltaMin',rawValue:107,value:null,valueType:'na',emitted:true}],profileSnapshot:{name:'工况 A',version:2,mode:'replace',parameters:{deltaMin:0,defVal:{type:'na'}}}
  }}});});
  await openView(page,'otherSettings');await page.getByRole('tab',{name:zh?'数据清洗方案':'Cleaning profiles',exact:true}).click();
  await expect(page.getByRole('button',{name:zh?'新增清洗方案':'Add cleaning profile',exact:true})).toBeDisabled();
  await page.getByRole('combobox',{name:zh?'预览表计':'Preview meter',exact:true}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('测试分表',{exact:true}).click();
  await page.getByLabel(zh?'预览开始时间':'Preview start time',{exact:true}).fill('2026-10-20T00:00');
  await page.getByLabel(zh?'预览结束时间':'Preview end time',{exact:true}).fill('2026-10-21T00:00');
  const run=page.getByRole('button',{name:zh?/运行清洗预览/:/Run cleaning preview/});await run.click();
  await expect(page.getByText(zh?'清洗统计':'Cleaning statistics',{exact:true})).toBeVisible();
  const chart=page.getByRole('img',{name:zh?'原始读数折线与清洗后用量柱状图':'Raw reading line chart and cleaned consumption bar chart',exact:true});
  await expect(chart.locator('canvas')).toBeVisible();
  await page.getByRole('button',{name:zh?'定位下一处异常':'Locate next anomaly',exact:true}).click();
  await expect(page.locator('.cleaning-chart-focus')).toContainText(zh?'低于最小增量':'Below minimum delta');
  if(zh&&!mobile)await chart.screenshot({path:'../../out/cleaning-chart-fixture-zh-desktop.png'});
  await page.getByRole('button',{name:zh?'查看全部':'Show all',exact:true}).click();
  await expect(page.locator('.cleaning-chart-focus')).toHaveCount(0);
  expect(await chart.evaluate(element=>element.getBoundingClientRect().width)).toBeLessThanOrEqual(mobile?390:1440);
  expect(previews[0]).toMatchObject({nodeId:'meter1',from:'2026-10-20T00:00:00+08:00',to:'2026-10-21T00:00:00+08:00'});
  await expect(page.getByRole('cell',{name:'NA',exact:true})).toBeVisible();
  await page.getByText(zh?'查看清洗诊断与方案快照':'View cleaning diagnostics and profile snapshot',{exact:true}).click();
  await expect(page.getByText('工况 A',{exact:true})).toBeVisible();
  await page.getByLabel(zh?'预览结束时间':'Preview end time',{exact:true}).fill('2026-12-21T00:00');
  await expect(run).not.toHaveClass(/ant-btn-loading/);await run.click();
  await expect(page.getByText(zh?'预览区间不能超过 31 天':'The preview range cannot exceed 31 days',{exact:true})).toBeVisible();
  expect(previews).toHaveLength(1);expect(state.requests.some(row=>row.path==='records')).toBe(false);
 });
});

for(const external of [false,true])test(`equipment cleaning ${external?'preserves external management':'saves selected profile'}`,async({page})=>{
 const records:EnerCubixRecord[]=[{id:'site',kind:'space',name:'园区',nativeSourceKind:'site',nativeSourceId:'site',nativeReadonly:true},{id:'cat',kind:'category',name:'电力',unit:'kWh'},{id:'profile',kind:'cleaningProfile',name:'工况 A',mode:'drop',parameters:{deltaMin:0,timeMax:'1h',defNull:true}},{id:'equip',mod:'m1',kind:'meter',name:'总电表',pointId:'p',categoryId:'cat',unit:'kWh',nativeEquip:true,nativeSpaceId:'equip',nativeTreeParentId:'site',...(external?{cleaningStatus:'externalFunctionManaged',hisFunc:'customFn'}:{})}];
 const state=await installTransport(page,{records,spaceSource:'fin',storageModel:'nativeEquip'});await openView(page,'tree');
 await page.locator('.meter-tree-panel').getByRole('button',{name:'全部对象',exact:true}).click();await page.getByRole('button',{name:'编辑总电表',exact:true}).click();
 if(external){await expect(page.getByText('外部函数管理',{exact:true})).toBeVisible();await expect(page.getByRole('switch',{name:'数据清洗',exact:true})).toHaveCount(0);}
 else{await page.getByRole('switch',{name:'数据清洗',exact:true}).check();await page.getByRole('combobox',{name:'清洗方案',exact:true}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('工况 A',{exact:true}).click();}
 await page.getByRole('button',{name:'保存配置',exact:true}).click();await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
 const saved=state.requests.find(row=>row.path==='records')!.body.record;
 if(external){expect(saved).toMatchObject({hisFunc:'customFn'});expect(saved).not.toHaveProperty('cleaningEnabled');}else expect(saved).toMatchObject({cleaningEnabled:true,cleaningProfileId:'profile'});
});

test('disabled cleaning allows clearing a linked profile before deletion',async({page})=>{
 const state=await installTransport(page,{records:[{id:'site',kind:'space',name:'园区',nativeSourceKind:'site',nativeSourceId:'site',nativeReadonly:true},{id:'cat',kind:'category',name:'电力',unit:'kWh'},{id:'profile',mod:'p1',kind:'cleaningProfile',name:'工况 A',version:1,mode:'drop',parameters:{deltaMin:0,timeMax:'1h',defNull:true}},{id:'equip',mod:'m1',kind:'meter',name:'总电表',pointId:'p',categoryId:'cat',unit:'kWh',nativeEquip:true,nativeSpaceId:'equip',nativeTreeParentId:'site',cleaningEnabled:true,cleaningProfileId:'profile'}],spaceSource:'fin',storageModel:'nativeEquip'});
 await openView(page,'tree');await page.locator('.meter-tree-panel').getByRole('button',{name:'全部对象',exact:true}).click();await page.getByRole('button',{name:'编辑总电表',exact:true}).click();
 await page.getByRole('switch',{name:'数据清洗',exact:true}).uncheck();
 const select=page.getByRole('combobox',{name:'清洗方案',exact:true});await expect(select).toBeEnabled();
 const field=page.locator('.ant-form-item').filter({has:select});await field.hover();await field.locator('.ant-select-clear').click();
 await page.getByRole('button',{name:'保存配置',exact:true}).click();await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
 const saved=state.requests.find(row=>row.path==='records')!.body.record;expect(saved).toMatchObject({cleaningEnabled:false});expect(saved).not.toHaveProperty('cleaningProfileId');
 await openView(page,'otherSettings');await page.getByRole('tab',{name:'数据清洗方案',exact:true}).click();
 await page.getByRole('row').filter({hasText:'工况 A'}).getByRole('button',{name:/删\s*除/}).click();await page.locator('.ant-popconfirm').getByRole('button',{name:/删\s*除/}).click();
 await expect.poll(()=>state.records.some(row=>row.id==='profile')).toBe(false);
});

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`virtual cleaning provenance ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('shows both source corrections, localized rules and processing basis',async({page})=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  await installTransport(page,{canWrite:false});
  const start='2026-10-20T00:00:00+08:00',end='2026-10-20T01:00:00+08:00';
  await page.route('**/v1/cleaning/preview',route=>route.fulfill({json:{ok:true,data:{pointId:'point2',unit:'kWh',from:start,to:'2026-10-20T02:00:00+08:00',raw:[{ts:start,value:999},{ts:end,value:999}],cleaned:[{ts:start,value:25},{ts:end,value:14}],summary:{rolloverCount:2,outputCount:2,processingScope:'sourceIntervals'},profileSnapshot:{},details:['source-a','source-b'].map((pointId,index)=>({ts:start,intervalStart:start,intervalEnd:end,pointId,rawValue:index?3:12,reason:'rollover',rule:'hisTotalizedRollover',value:index?5:20,valueType:'number',unit:'kWh',emitted:true}))}}}));
  await openView(page,'otherSettings');await page.getByRole('tab',{name:zh?'数据清洗方案':'Cleaning profiles',exact:true}).click();
  await page.getByRole('combobox',{name:zh?'预览表计':'Preview meter',exact:true}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('测试总表',{exact:true}).click();
  await page.getByLabel(zh?'预览开始时间':'Preview start time',{exact:true}).fill('2026-10-20T00:00');
  await page.getByLabel(zh?'预览结束时间':'Preview end time',{exact:true}).fill('2026-10-20T02:00');
  await page.getByRole('button',{name:zh?/运行清洗预览/:/Run cleaning preview/}).click();
  await expect(page.getByRole('img',{name:zh?'原始读数折线与清洗后用量柱状图':'Raw reading line chart and cleaned consumption bar chart',exact:true}).locator('canvas')).toBeVisible();
  await expect(page.getByText(zh?'源点区间处理次数；输出点数和覆盖率按当前对象计算':'Source interval processing counts; output readings and coverage describe the current object',{exact:true})).toBeVisible();
  const locate=page.getByRole('button',{name:zh?'定位下一处异常':'Locate next anomaly',exact:true});
  await locate.click();await expect(page.locator('.cleaning-chart-focus')).toContainText('source-a');
  await locate.click();await expect(page.locator('.cleaning-chart-focus')).toContainText('source-b');
  await page.getByText(zh?'查看清洗诊断与方案快照':'View cleaning diagnostics and profile snapshot',{exact:true}).click();
  await expect(page.getByRole('cell',{name:zh?'计数周期（hisTotalizedRollover）':'Counter period (hisTotalizedRollover)',exact:true})).toHaveCount(2);
  await expect(page.getByRole('cell',{name:zh?'回绕已修正':'Counter rollover corrected',exact:true})).toHaveCount(2);
 });
});
