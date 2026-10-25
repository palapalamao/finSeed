import {test,expect} from '@playwright/test';
import {installTransport,openView,checkNode,resultFor} from './fixtures';
import type {ReportRequest} from '../../src/types';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`cleaning diagnostic labels ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('localizes report and preview diagnostic titles and boolean values',async({page},testInfo)=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  await installTransport(page,{canWrite:false});
  const detail={previousValue:32760,emitted:true,substituted:false,intervalSeconds:3600};
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
   const result=resultFor(route.request().postDataJSON() as ReportRequest);
   result.extra={cleaning:[{summary:{rolloverCount:2},details:[detail,{...detail,emitted:false,substituted:true}]}]};
   await route.fulfill({json:{ok:true,data:result}});
  });
  await openView(page,'profile');await checkNode(page);
  await page.getByRole('button',{name:zh?/查\s*询/:/Query$/}).click();
  const report=page.locator('.cleaning-report-summary');
  await report.getByText(zh?'查看清洗诊断与方案快照':'View cleaning diagnostics and profile snapshot',{exact:true}).click();
  const labels=zh?['前一读数','是否输出','是否替代','区间时长（秒）']:['Previous reading','Output emitted','Value substituted','Interval duration (seconds)'];
  for(const title of labels)await expect(report.getByRole('columnheader',{name:title,exact:true})).toHaveCount(1);
  await expect(report.getByRole('cell',{name:zh?'是':'Yes',exact:true})).toHaveCount(2);
  await expect(report.getByRole('cell',{name:zh?'否':'No',exact:true})).toHaveCount(2);
  for(const title of Object.keys(detail))await expect(report.getByRole('columnheader',{name:title,exact:true})).toHaveCount(0);
  for(const value of ['true','false'])await expect(report.getByRole('cell',{name:value,exact:true})).toHaveCount(0);
  await report.scrollIntoViewIfNeeded();await page.screenshot({path:testInfo.outputPath('report-diagnostics.png')});
  await page.route('**/v1/cleaning/preview',route=>route.fulfill({json:{ok:true,data:{pointId:'point2',unit:'kWh',from:'2026-10-04T00:00:00+08:00',to:'2026-10-04T02:00:00+08:00',raw:[],cleaned:[],summary:{},profileSnapshot:{},details:[detail]}}}));
  await openView(page,'otherSettings');await page.getByRole('tab',{name:zh?'数据清洗方案':'Cleaning profiles',exact:true}).click();
  await page.getByRole('combobox',{name:zh?'预览表计':'Preview meter',exact:true}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('测试总表',{exact:true}).click();
  await page.getByRole('button',{name:zh?/运行清洗预览/:/Run cleaning preview/}).click();
  const preview=page.locator('.cleaning-debug');await preview.getByText(zh?'查看清洗诊断与方案快照':'View cleaning diagnostics and profile snapshot',{exact:true}).click();
  for(const title of labels)await expect(preview.getByRole('columnheader',{name:title,exact:true})).toHaveCount(1);
  for(const title of Object.keys(detail))await expect(preview.getByRole('columnheader',{name:title,exact:true})).toHaveCount(0);
  for(const value of ['true','false'])await expect(preview.getByRole('cell',{name:value,exact:true})).toHaveCount(0);
 });
});
