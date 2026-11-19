import {expect,test} from '@playwright/test';
import {readFileSync,writeFileSync} from 'node:fs';
import {installTransport} from './fixtures';
import type {CockpitRequest,CockpitSnapshot} from '../../src/cockpitTypes';

const source=JSON.parse(readFileSync(new URL('../fixtures/cockpit-space-response.json',import.meta.url),'utf8')) as CockpitSnapshot;
const version=JSON.parse(readFileSync(new URL('../../package.json',import.meta.url),'utf8')).version;
const amounts=[{id:'native-amount',value:1363922.202},{id:'long-negative-amount',value:-9876543210.123}];

for(const language of ['zh-CN','en-US'])for(const amount of amounts)test('mobile cost amount and currency remain readable without scrolling '+amount.id+' '+language,async({page},info)=>{
 const requests:CockpitRequest[]=[],captures:unknown[]=[];
 const state=await installTransport(page,{userLocale:language,canWrite:false,spaceSource:'fin',records:[
  {id:'s',kind:'space',name:'Site 原名',nativeReadonly:true,nativeSourceKind:'site'},
  {id:'f',kind:'space',name:'Floor 原名',parentId:'s',nativeReadonly:true,nativeSourceKind:'floor'},
  ...['a','b'].map(id=>({id,kind:'meter' as const,name:'Meter '+id,nativeEquip:true,nativeTreeParentId:'f',pointId:'p'+id,categoryId:'c'})),
  {id:'c',kind:'category',name:'Electricity 原名',unit:'kWh'}
 ]});
 await page.route('**/api/testproject/ext/finEnergy/v1/catalog',route=>route.fulfill({json:{ok:true,data:{version,project:'testproject',spaceSource:'fin',user:{name:state.username,canWrite:false},records:state.records}}}));
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit',route=>{
  const request=route.request().postDataJSON() as CockpitRequest;requests.push(request);
  const snapshot=structuredClone(source);snapshot.context.project='testproject';snapshot.requestId=request.requestId;
  const cost=snapshot.modules.kpis!.data!.values.find(metric=>metric.id==='cost')!;
  Object.assign(cost,{value:amount.value,valueType:'number',valueBasis:'knownSubtotal',quality:'filtered',unit:'CNY',reasonCodes:[]});
  return route.fulfill({json:{ok:true,data:snapshot}});
 });
 await page.route('**/api/testproject/ext/finEnergy/v1/cockpit/assets',route=>route.fulfill({json:{ok:true,data:{projectId:'testproject',manifestMod:null,selectedId:null,items:[],canWrite:false}}}));
 await page.goto('/#/cockpit?project=testproject');
 const cost=page.locator('.cockpit-kpi[data-metric="cost"]'),number=cost.locator('.cockpit-value');
 const expected=new Intl.NumberFormat(language,{maximumFractionDigits:3}).format(amount.value);
 await expect(number).toHaveText(expected);
 await expect(cost.getByRole('heading')).toHaveText(language==='zh-CN'?'关注能源费用':'Focus energy cost');
 await expect(cost.locator('.cockpit-card-number>small')).toHaveText('CNY');
 const snapshotId=await page.locator('.cockpit-snapshot').getAttribute('data-cockpit-snapshot');
 // Include the narrower application widths observed inside FIN's mobile shell.
 for(const width of [305,320,375,390,1366]){
  await page.setViewportSize({width,height:844});
  // Reproduce FIN's observed 98px inner amount slot as a constrained-layout
  // fixture; the other widths also exercise the unmodified application layout.
  await number.evaluate((element,width)=>{element.style.maxWidth=width<=320?'98px':'';},width);
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  const geometry=await cost.evaluate(element=>{
   const value=element.querySelector<HTMLElement>('.cockpit-value')!,unit=element.querySelector<HTMLElement>('.cockpit-card-number>small')!,line=value.parentElement!;
   const box=(el:Element)=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height};};
   const range=document.createRange();range.selectNodeContents(value);
   const lines=new Map<number,string>(),walker=document.createTreeWalker(value,NodeFilter.SHOW_TEXT);
   while(walker.nextNode()){
    const node=walker.currentNode;
    for(let i=0;i<(node.textContent||'').length;i++){
     const character=document.createRange();character.setStart(node,i);character.setEnd(node,i+1);
     const y=Math.round(character.getBoundingClientRect().y);
     lines.set(y,(lines.get(y)||'')+node.textContent![i]);
    }
   }
   return {value:box(value),unit:box(unit),line:box(line),card:box(element),clientWidth:value.clientWidth,scrollWidth:value.scrollWidth,lineClientWidth:line.clientWidth,lineScrollWidth:line.scrollWidth,fontSize:Number.parseFloat(getComputedStyle(value).fontSize),renderedLines:[...lines.values()],glyphs:[...range.getClientRects()].map(r=>({x:r.x,y:r.y,right:r.right,bottom:r.bottom}))};
  });
  expect(geometry.scrollWidth,'all amount digits must be readable without internal horizontal scrolling').toBeLessThanOrEqual(geometry.clientWidth);
  expect(geometry.lineScrollWidth,'amount and currency must stay inside the card').toBeLessThanOrEqual(geometry.lineClientWidth);
  expect(geometry.fontSize,'keep readable numerals rather than shrinking the page').toBeGreaterThanOrEqual(14);
  if(amount.id==='native-amount')expect(geometry.renderedLines,'the observed fee should remain one readable number').toHaveLength(1);
  else for(const line of geometry.renderedLines.slice(0,-1))expect(line,'wrap long fees at a thousands-group boundary').toMatch(/,$/);
  for(const glyph of geometry.glyphs){
   expect(glyph.x).toBeGreaterThanOrEqual(geometry.value.x-1);
   expect(glyph.right).toBeLessThanOrEqual(geometry.value.right+1);
   expect(glyph.bottom).toBeLessThanOrEqual(geometry.line.bottom+2);
  }
  expect(geometry.unit.right).toBeLessThanOrEqual(geometry.card.right);
  const boxes=await page.locator('.cockpit-kpi').evaluateAll(elements=>elements.map(element=>{const r=element.getBoundingClientRect();return {x:r.x,y:r.y};}));
  if(width<=390){expect(boxes[0].y).toBe(boxes[1].y);expect(boxes[2].y).toBe(boxes[3].y);expect(boxes[2].y).toBeGreaterThan(boxes[0].y);expect(boxes[1].x).toBeGreaterThan(boxes[0].x);}
  await expect(number).toHaveText(expected);
  expect(await cost.locator('.cockpit-card-number').ariaSnapshot()).toContain(expected);
  await expect(page.locator('.cockpit-snapshot')).toHaveAttribute('data-cockpit-snapshot',snapshotId!);
  captures.push({width,language,amount:expected,unit:'CNY',snapshotId,...geometry});
  await page.locator('.cockpit-kpis').screenshot({path:info.outputPath('cost-'+width+'.png')});
 }
 expect(requests).toHaveLength(1);
 writeFileSync(info.outputPath('cost-layout.json'),JSON.stringify({classification:'Controlled production preview with an explicit cost-layout fixture; not FIN business data acceptance',captures,requests},null,2));
});
