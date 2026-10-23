import {test,expect} from '@playwright/test';
import {installTransport,openView,testRecords,query} from './fixtures';
import type {ReportRequest,ReportResult} from '../../src/types';
import {palette,loadBandColors} from '../../src/chartOptions';

test('daily load uses distinct meter colors without a calendar and retains an explicit band view',async({page},testInfo)=>{
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 const request:ReportRequest={kind:'daily',dimension:'metering',nodeIds:['master1','meter1','meter2'],from:'2026-10-19T00:00:00+08:00',to:'2026-10-22T00:00:00+08:00',period:'day',metric:'energy',perArea:false};
 const records=[...testRecords(),{id:'meter2',kind:'meter' as const,name:'空调分表',pointId:'point4',unit:'kWh',categoryId:'cat1'},{id:'daily-template',kind:'template' as const,name:'三表日均负荷',request}];
 const state=await installTransport(page,{records});
 await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{
  const current=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:current as unknown as Record<string,unknown>});
  const series=current.nodeIds.map((id,index)=>({id,nodeId:id,name:records.find(row=>row.id===id)!.name,categoryId:'cat1',unit:'kWh',points:Array.from({length:24},(_,hour)=>({ts:`2000-01-01T${String(hour).padStart(2,'0')}:00:00+08:00`,value:hour===2&&index===1?null:hour===3?0:10+index*5+hour%6,quality:hour===2&&index===1?'missing':'ok',sourceIds:['point'+(index+1)],band:'unknown' as const}))}));
  const result:ReportResult={kind:'daily',from:current.from,to:current.to,period:current.period,series,rows:series.flatMap(s=>s.points.map(p=>({nodeId:s.nodeId,name:s.name,categoryId:'cat1',unit:'kWh',...p}))),summary:{},warnings:['未配置日历，无法划分峰谷平时段'],extra:{loadBands:series.map(s=>({name:s.name,band:'unknown',unit:'kWh',value:500.12345})),loadBandsAggregation:'intervalTotal'}};
  await route.fulfill({json:{ok:true,data:result}});
 });
 await openView(page,'daily');await page.locator('.template-select').getByRole('combobox').press('ArrowDown');await page.locator('.ant-select-dropdown:visible').getByText('三表日均负荷',{exact:true}).click();await query(page);
 await expect(page.getByRole('radio',{name:'按表计配色',exact:true})).toBeChecked();await expect(page.locator('.load-band-legend')).toContainText('不同颜色区分计量对象');
 const pixels=async(colors:string[])=>page.locator('.report-chart canvas').evaluate((canvas:HTMLCanvasElement,colors)=>{const data=canvas.getContext('2d')!.getImageData(0,0,canvas.width,canvas.height).data;return colors.map(hex=>{const rgb=hex.match(/\w\w/g)!.map(part=>parseInt(part,16));let n=0;for(let i=0;i<data.length;i+=4)if(Math.abs(data[i]-rgb[0])<3&&Math.abs(data[i+1]-rgb[1])<3&&Math.abs(data[i+2]-rgb[2])<3&&data[i+3]>0)n++;return n;});},colors);
 await expect.poll(async()=>Math.min(...await pixels(palette.slice(0,3)))).toBeGreaterThan(1000);
 await page.screenshot({path:testInfo.outputPath('daily-meter-colors.png'),fullPage:true});
 await page.locator('label').filter({has:page.getByRole('radio',{name:'按峰谷平配色',exact:true})}).click();await expect(page.locator('.load-band-legend')).toContainText('未分类小时显示灰色');await expect.poll(async()=>(await pixels([loadBandColors.unknown]))[0]).toBeGreaterThan(5000);
 await expect(page.locator('.report-surface')).toContainText('500.12');await expect(page.locator('.report-surface')).toContainText('missing');expect(state.requests.filter(row=>row.path==='report')).toHaveLength(1);expect(errors).toEqual([]);
});
