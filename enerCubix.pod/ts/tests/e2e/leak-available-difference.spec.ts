import {readFileSync} from 'node:fs';
import JSZip from 'jszip';
import {test,expect} from '@playwright/test';
import {installTransport} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';

for(const language of ['zh-CN','en-US'])test(`shows and exports the available-use difference in ${language}`,async({page},testInfo)=>{
 const en=language==='en-US',errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 const request:ReportRequest={kind:'leak',dimension:'metering',nodeIds:['m'],from:'2026-10-01T00:00:00+08:00',to:'2026-11-01T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
 const records:EnerCubixRecord[]=[{id:'e',kind:'category',name:en?'Electricity':'电能',unit:'kWh'},{id:'m',kind:'totalMeter',name:en?'Main meter':'总表',pointId:'p-main',categoryId:'e',unit:'kWh'},...['a','b','c'].map((id,i)=>({id,kind:'meter' as const,name:en?`Submeter ${i+1}`:`分表${i+1}`,pointId:'p-'+id,categoryId:'e',unit:'kWh',meterParentId:'m'})),{id:'saved-leak',kind:'template',name:'Available balance',request}];
 const total={nodeId:'m',categoryId:'e',unit:'kWh',knownTotal:924821,knownSubmeter:974613,difference:null,percentage:null,balanceMode:'consistency',membershipQuality:'ok'};
 const result:ReportResult={kind:'leak',from:request.from,to:request.to,asOf:'2026-10-27T22:59:35+08:00',period:'day',series:[{id:'m|e',nodeId:'m',name:en?'Main meter':'总表',categoryId:'e',unit:'kWh',points:[{ts:request.from,value:null,knownValue:924821,quality:'missing',knownQuality:'filtered',sourceIds:['p-main']}]}],rows:[{...total,ts:request.from}],summary:{},warnings:[],extra:{relationBasis:'current',leakTotals:[total],leakBranches:['a','b','c'].map((id,i)=>({nodeId:'m',branchId:id,name:records[i+2].name,categoryId:'e',unit:'kWh',ts:request.from,value:null,knownValue:[267898,530636,176079][i],quality:'missing',sourceIds:['p-'+id]}))}};

 await installTransport(page,{userLocale:language,records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',r=>r.fulfill({json:{ok:true,data:result}}));
 await page.goto('/#/leak?project=testproject&template=saved-leak');
 await page.getByRole('button',{name:en?'Query':/查\s*询/,exact:true}).click();
 const scope=page.locator('.leak-overview'),cards=scope.locator('.metric-readout');
 await expect(cards.nth(0)).toContainText('924821');await expect(cards.nth(1)).toContainText('974613');
 await expect(cards.nth(2)).toContainText(en?'Available usage difference (main − submeters)':'已有用量差值（总表 − 分表）');
 await expect(cards.nth(2)).toContainText('-49792');await expect(cards.nth(3)).toContainText('-5.38');
 await expect(cards.nth(3)).toContainText(en?'Difference / available main-meter usage':'差值 ÷ 总表已有用量');
 await expect(scope).toContainText(en?'Meter coverage may differ':'各表数据覆盖可能不同');
 for(const width of [1440,390,360]){
  await page.setViewportSize({width,height:960});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await scope.screenshot({path:testInfo.outputPath(`available-difference-${language}-${width}.png`)});
 }
 await page.getByRole('button',{name:en?'Export current report':'导出当前报表'}).click();
 const pending=page.waitForEvent('download');await page.getByRole('menuitem',{name:/Excel/}).click();const download=await pending,path=testInfo.outputPath(download.suggestedFilename());await download.saveAs(path);
 const zip=await JSZip.loadAsync(readFileSync(path)),strings=await zip.file('xl/sharedStrings.xml')!.async('string');
 expect(strings).toContain(en?'Available usage difference (main − submeters)':'已有用量差值（总表 − 分表）');
 expect(strings).toContain('-49792');expect(strings).toContain('-5.383960788087641');
 expect(result.extra?.leakTotals).toEqual([total]);expect(total.difference).toBeNull();expect(total.percentage).toBeNull();expect(errors).toEqual([]);
});
