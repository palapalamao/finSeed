import {readFileSync} from 'node:fs';
import {test,expect} from '@playwright/test';
import {installTransport,openView,closeObjects} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

// Captured from the isolated FIN history adapter; transport replay verifies UI
// presentation only. Native execution and its audit are separate release evidence.
const native=JSON.parse(readFileSync(new URL('../fixtures/leak-native-report.json',import.meta.url),'utf8')) as {request:ReportRequest;report:ReportResult};
for(const language of ['zh-CN','en-US'])test(`renders available own consumption and an unavailable balance in ${language} on desktop and mobile`,async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',err=>errors.push(err.message));

 const result=structuredClone(native.report),request=native.request;
 const master=request.nodeIds[0],own=result.extra!.leakOwnUsage as Record<string,unknown>[],category=String(own.find(row=>row.nodeId===master)!.categoryId);
 const records:EnerCubixRecord[]=[{id:category,kind:'category',name:'Electric',unit:'kWh'},...own.map(row=>({id:String(row.nodeId),kind:row.nodeId===master?'totalMeter' as const:'meter' as const,name:String(row.name),pointId:String(row.pointId),categoryId:category,includeInTotals:true,...(row.nodeId===master?{autoSum:true}:{meterParentId:master})})),{id:'native-template',kind:'template',name:'Stored balance',request}];
 const state=await installTransport(page,{userLocale:language,records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  state.requests.push({path:'report',body:route.request().postDataJSON()});
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'leak');
 await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('Stored balance',{exact:true}).click();
 await closeObjects(page);await page.getByRole('button',{name:language==='zh-CN'?/查\s*询/:'Query',exact:true}).click();
 const overview=page.locator('.leak-overview');
 await expect(overview.locator('.report-chart canvas')).toHaveCount(1);
 await expect(overview).toContainText(language==='zh-CN'?'各表自身已有用量':'Each meter’s own available consumption');
 await expect(overview).toContainText(language==='zh-CN'?'不能据此判定泄漏':'cannot establish leakage');
 await expect(overview.locator('.metric-readout').nth(0)).toContainText('60');
 await expect(overview.locator('.metric-readout').nth(2)).toContainText('—');
 const sent=state.requests.filter(item=>item.path==='report').at(-1)!.body;
 expect(sent.from).toBe(request.from);expect(sent.to).toBe(request.to);
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:960});
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await expect(overview.locator('.report-chart canvas')).toBeVisible();
  await overview.screenshot({path:testInfo.outputPath(`native-leak-${language}-${width}.png`)});
 }
 expect(errors).toEqual([]);expect(result).toEqual(native.report);
});
