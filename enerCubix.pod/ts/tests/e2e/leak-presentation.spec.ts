import {test,expect,type Page} from '@playwright/test';
import {openObjects,installTransport,openView,query} from './fixtures';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';

async function setup(page:Page,template=true){
 const master='master',category='electric';
 const request:ReportRequest={kind:'leak',dimension:'metering',nodeIds:[master],from:'2026-10-19T00:00:00+08:00',to:'2026-10-26T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
 const records:EnerCubixRecord[]=[{id:category,kind:'category',name:'电能',unit:'kWh'},{id:master,kind:'totalMeter',name:'10F总表',pointId:'point2',categoryId:category,unit:'kWh'},...['照明','空调','插座','其他'].map((name,i)=>({id:'branch'+i,kind:'meter' as const,name:'10F'+name+'分表',pointId:'point1',categoryId:category,meterParentId:master,includeInTotals:true})),{id:'leak-template',kind:'template',name:'10F总分表对照',request}];
 const state=await installTransport(page,{records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const current=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:current as unknown as Record<string,unknown>});
  const masters=[300,420,390,460,410,450,400],values=[[140,150,145,160,150,155,140],[100,110,100,120,110,120,110],[60,70,65,80,65,75,65],[50,60,55,70,60,65,55]];
  const weekly=current.period==='week';const totalValues=weekly?[masters.reduce((a,b)=>a+b,0)]:masters;const branchValues=weekly?values.map(row=>[row.reduce((a,b)=>a+b,0)]):values;
  const times=totalValues.map((_,i)=>`2026-10-${19+i}T00:00:00+08:00`);
  const rows=totalValues.map((total,i)=>{const submeter=branchValues.reduce((sum,row)=>sum+row[i],0),difference=total-submeter;return {key:times[i],nodeId:master,name:'10F总表',categoryId:category,unit:'kWh',ts:times[i],total,submeter,difference,percentage:difference/total*100,value:difference,quality:'ok',sourceIds:['point1','point2']};});
  const total=masters.reduce((a,b)=>a+b,0),submeter=values.flat().reduce((a,b)=>a+b,0),difference=total-submeter;
  const result:ReportResult={kind:'leak',from:current.from,to:current.to,period:current.period,series:[{id:master+'|'+category,nodeId:master,name:'10F总表',categoryId:category,unit:'kWh',points:rows.map(row=>({ts:row.ts,value:row.difference,quality:'ok',sourceIds:row.sourceIds}))}],rows,summary:{},warnings:[],extra:{leakTotals:[{nodeId:master,categoryId:category,unit:'kWh',total,submeter,difference,percentage:difference/total*100}],leakBranches:branchValues.flatMap((values,i)=>values.map((value,j)=>({nodeId:master,branchId:'branch'+i,name:records[i+2].name,categoryId:category,unit:'kWh',ts:times[j],value,quality:'ok',sourceIds:['point1']})))}};
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'leak');
 if(template){await page.locator('.template-select').getByRole('combobox').click();await page.locator('.ant-select-dropdown:visible').getByText('10F总分表对照',{exact:true}).click();await query(page);}
 return state;
}
test('shows one total bar beside a four-branch stack for every day and supports weekly buckets',async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));const state=await setup(page);
 await expect(page.locator('.leak-overview')).toContainText('每个时段两根柱');await expect(page.locator('.leak-overview .report-chart canvas')).toHaveCount(1);await expect(page.locator('.leak-overview')).toContainText('分表合计大于总表');await expect(page.locator('.report-details')).not.toHaveAttribute('open');
 await page.screenshot({path:testInfo.outputPath('leak-grouped-stacks.png'),fullPage:true});
 await page.locator('.filter-field').filter({hasText:'汇总间隔'}).locator('.ant-select-selector').click();await page.locator('.ant-select-dropdown:visible').getByText('周',{exact:true}).click();await query(page);expect(state.requests.filter(row=>row.path==='report').at(-1)?.body.period).toBe('week');await expect(page.locator('.print-heading')).toContainText('汇总间隔：周');await page.screenshot({path:testInfo.outputPath('leak-week.png'),fullPage:true});
 await page.setViewportSize({width:390,height:844});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:testInfo.outputPath('leak-mobile.png'),fullPage:true});expect(errors).toEqual([]);
});
test('only a master with direct eligible branches is selectable',async({page})=>{
 await setup(page,false);await page.getByRole('radiogroup',{name:'分析视角'}).getByText('计量',{exact:true}).click();await openObjects(page);
 const node=(name:string)=>page.locator('.object-panel .ant-tree-treenode').filter({hasText:name});const master=node('10F总表');await expect(master.locator('.ant-tree-checkbox')).not.toHaveClass(/disabled/);
 if(await master.locator('.ant-tree-switcher_close').count())await master.locator('.ant-tree-switcher').click();
 await expect(node('10F照明分表').locator('.ant-tree-checkbox')).toHaveClass(/disabled/);await master.locator('.ant-tree-checkbox').click();await query(page);await expect(page.locator('.leak-overview')).toContainText('10F总表');
});
