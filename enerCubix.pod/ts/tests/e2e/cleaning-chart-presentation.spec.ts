import {test,expect} from '@playwright/test';
import {PNG} from 'pngjs';
import {installTransport,openView} from './fixtures';

for(const locale of ['zh-CN','en-US'])for(const mobile of [false,true])test.describe(`cleaning chart ${locale} ${mobile?'mobile':'desktop'}`,()=>{
 test.use({locale});
 test('keeps both numeric axes visible for a large total meter reading',async({page},testInfo)=>{
  const zh=locale==='zh-CN';if(mobile)await page.setViewportSize({width:390,height:844});
  const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
   const fill=CanvasRenderingContext2D.prototype.fillText;
   (window as any).axisLabels=[];
   CanvasRenderingContext2D.prototype.fillText=function(text,x,y,...rest){
    if(/^\d[\d,.]*$/.test(text)){
     const width=this.measureText(text).width,matrix=this.getTransform();
     const left=x-(this.textAlign==='right'||this.textAlign==='end'?width:this.textAlign==='center'?width/2:0);
     (window as any).axisLabels.push({text,left:(matrix.a*left+matrix.e)/devicePixelRatio,right:(matrix.a*(left+width)+matrix.e)/devicePixelRatio,width:this.canvas.width/devicePixelRatio});
    }
    return fill.call(this,text,x,y,...rest);
   };
  });
  await installTransport(page,{canWrite:false});
  const times=Array.from({length:6},(_,i)=>`2026-10-20T00:${String(i*10).padStart(2,'0')}:00+08:00`);
  await page.route('**/v1/cleaning/preview',route=>route.fulfill({json:{ok:true,data:{pointId:'total',unit:'kWh',from:times[0],to:'2026-10-20T01:00:00+08:00',raw:times.map((ts,i)=>({ts,value:9876543210+i*25,valueType:'number'})),cleaned:times.slice(0,-1).map((ts,i)=>({ts,value:[25,12,0,null,35][i],valueType:i===3?'na':'number'})),summary:{outputCount:5},details:[],profileSnapshot:{}}}}));
  await openView(page,'otherSettings');await page.getByRole('tab',{name:zh?'数据清洗方案':'Cleaning profiles',exact:true}).click();
  await page.getByRole('combobox',{name:zh?'预览表计':'Preview meter',exact:true}).click();await page.locator('.ant-select-dropdown:visible').getByTitle('测试总表',{exact:true}).click();
  await page.getByLabel(zh?'预览开始时间':'Preview start time',{exact:true}).fill('2026-10-20T00:00');
  await page.getByLabel(zh?'预览结束时间':'Preview end time',{exact:true}).fill('2026-10-20T01:00');
  await page.getByRole('button',{name:zh?/运行清洗预览/:/Run cleaning preview/}).click();
  const chart=page.locator('.cleaning-preview-chart');await expect(chart.locator('canvas')).toBeVisible();
  const rendered=PNG.sync.read(await chart.screenshot({path:testInfo.outputPath('total-meter-chart.png')}));
  let tallestBar=0;
  for(let x=0;x<rendered.width;x++){
   let pixels=0;
   for(let y=Math.ceil(rendered.height/2);y<rendered.height;y++){
    const offset=(y*rendered.width+x)*4;
    if(rendered.data[offset]===19&&rendered.data[offset+1]===127&&rendered.data[offset+2]===122)pixels++;
   }
   tallestBar=Math.max(tallestBar,pixels);
  }
  expect(tallestBar).toBeGreaterThan(20);
  const labels=await page.evaluate(()=>(window as any).axisLabels as {text:string;left:number;right:number;width:number}[]);
  expect(labels.length).toBeGreaterThan(2);
  expect(labels.filter(label=>label.left<0||label.right>label.width)).toEqual([]);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  expect(errors).toEqual([]);
 });
});
