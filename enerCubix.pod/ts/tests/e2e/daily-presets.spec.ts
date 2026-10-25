import {test,expect} from '@playwright/test';
import {installTransport,openView,testRecords} from './fixtures';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`daily presets ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('offers today and yesterday, queries their bounds and saves a rolling template',async({page})=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  await page.clock.setFixedTime(new Date('2026-10-24T14:37:22+08:00'));
  const state=await installTransport(page,{records:[...testRecords(),{id:'daily',kind:'template',name:'每日测试',preset:'today',request:{kind:'profile',dimension:'space',nodeIds:['meter1'],from:'2000-01-01T00:00:00+08:00',to:'2000-01-02T00:00:00+08:00',period:'hour',metric:'energy',perArea:false}}]});
  await openView(page,'profile');await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('每日测试',{exact:true}).click();
  const query=page.getByRole('button',{name:zh?'查询':'Query',exact:true});
  await query.click();await expect(page.locator('.report-chart canvas').first()).toBeVisible();
  expect(state.requests.filter(r=>r.path==='report').at(-1)?.body).toMatchObject({from:'2026-10-24T00:00:00+08:00',to:'2026-10-24T14:37:22+08:00'});
  const relative=page.locator('.filter-field').filter({has:page.locator('label',{hasText:zh?'相对时间':'Relative period'})}).getByRole('combobox');
  await relative.press('ArrowDown');const dropdown=page.locator('.ant-select-dropdown:visible');
  await expect(dropdown.getByText(zh?'今日':'Today',{exact:true})).toBeVisible();await dropdown.getByText(zh?'昨日':'Yesterday',{exact:true}).click();
  await query.click();await expect.poll(()=>state.requests.filter(r=>r.path==='report').length).toBe(2);
  expect(state.requests.filter(r=>r.path==='report').at(-1)?.body).toMatchObject({from:'2026-10-23T00:00:00+08:00',to:'2026-10-24T00:00:00+08:00'});
  await page.getByRole('button',{name:zh?'另存为模板':'Save as new template',exact:true}).click();
  await page.getByLabel(zh?'名称':'Name',{exact:true}).fill('昨日模板');
  const preset=page.getByLabel(zh?'相对时间预设':'Relative period preset',{exact:true});await preset.press('ArrowDown');
  await expect(page.locator('.ant-select-dropdown:visible').getByText(zh?'今日':'Today',{exact:true})).toBeVisible();await page.locator('.ant-select-dropdown:visible').getByText(zh?'昨日':'Yesterday',{exact:true}).click();
  await page.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();
  await expect.poll(()=>state.records.find(r=>r.name==='昨日模板')?.preset).toBe('yesterday');
  await page.goto(`/#/profile?project=testproject&template=${encodeURIComponent(state.records.find(r=>r.name==='昨日模板')!.id!)}`);
  await expect(page.locator('.template-select')).toContainText('昨日模板');
  await page.clock.setFixedTime(new Date('2026-10-25T10:00:00+08:00'));await query.click();
  await expect.poll(()=>state.requests.filter(r=>r.path==='report').length).toBe(3);
  expect(state.requests.filter(r=>r.path==='report').at(-1)?.body).toMatchObject({from:'2026-10-24T00:00:00+08:00',to:'2026-10-25T00:00:00+08:00'});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 });
});
