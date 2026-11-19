import {test,expect} from '@playwright/test';
import {installTransport,openView} from './fixtures';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`other settings ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('saves the interval and preserves overview settings',async({page})=>{
  const zh=locale==='zh-CN';
  if(mobile)await page.setViewportSize({width:390,height:844});
  const state=await installTransport(page);
  const before=structuredClone(state.records.find(row=>row.kind==='settings')!);
  await openView(page,'settings');
  const otherTab=page.getByRole('tab',{name:zh?'其他配置':'Other settings',exact:true});
  await otherTab.press('Enter');
  const interval=page.getByRole('spinbutton',{name:zh?'计算总表更新间隔（秒）':'Calculated meter update interval (seconds)',exact:true});
  const save=page.getByRole('button',{name:zh?/保存配置/:/Save configuration/});
  await expect(interval).toHaveValue('1');
  await interval.fill('10');
  await save.click();
  await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
  expect(state.requests.find(row=>row.path==='records')!.body.record).toMatchObject({...before,meterRollupSeconds:10});
  await expect(save).not.toHaveClass(/ant-btn-loading/);
  await page.getByRole('button',{name:zh?'刷新项目':'Refresh project',exact:true}).click();
  await expect(interval).toHaveValue('10');
  await interval.fill('');
  await save.click();
  await expect(page.getByText(zh?'请输入 1 至 3600 的整数秒数':'Enter a whole number of seconds from 1 to 3600',{exact:true})).toBeVisible();
  expect(state.requests.filter(row=>row.path==='records')).toHaveLength(1);
 });
});

test('read-only users cannot change project calculation settings',async({page})=>{
 await installTransport(page,{canWrite:false});await openView(page,'otherSettings');
 await expect(page.getByRole('spinbutton',{name:'计算总表更新间隔（秒）',exact:true})).toBeDisabled();
 await expect(page.getByRole('button',{name:'保存配置',exact:true})).toBeDisabled();
});

test('creates project settings when no overview configuration exists',async({page})=>{
 const state=await installTransport(page,{records:[]});await openView(page,'otherSettings');
 await page.getByRole('button',{name:'保存配置',exact:true}).click();
 await expect.poll(()=>state.requests.filter(row=>row.path==='records').length).toBe(1);
 expect(state.requests.find(row=>row.path==='records')!.body.record).toMatchObject({kind:'settings',meterRollupSeconds:1,rotationSeconds:20,visibleMetrics:['energy','cost','coal','co2']});
});
