import {readFileSync} from 'node:fs';
import JSZip from 'jszip';
import {test,expect} from '@playwright/test';
import {installTransport} from './fixtures';
import type {EnerCubixRecord,ReportRequest,ReportResult} from '../../src/types';
import type {EnergyFlowData,EnergyFlowNode} from '../../src/energyFlow';

const from='2026-10-01T00:00:00+08:00',to='2026-10-02T00:00:00+08:00';
function setup(en:boolean){
 const names={e:en?'Electricity':'电能',lighting:en?'Lighting':'照明用电',power:en?'Power':'动力用电',hvac:en?'HVAC':'空调用电',m:en?'Main meter':'总电表',a:en?'Lighting A':'照明表A',b:en?'Lighting B':'照明表B',c:en?'Power C':'动力表C'};
 const request:ReportRequest={kind:'utility',dimension:'metering',nodeIds:['a','b','c'],from,to,period:'day',metric:'energy',perArea:false};
 const records:EnerCubixRecord[]=[{id:'e',kind:'category',name:names.e,unit:'kWh'},...['lighting','power','hvac'].map(id=>({id,kind:'utility' as const,name:names[id as keyof typeof names],categoryId:'e'})),...['m','a','b','c'].map(id=>({id,kind:id==='m'?'totalMeter' as const:'meter' as const,name:names[id as keyof typeof names],pointId:id+'-point',categoryId:'e',utilityId:id==='m'?'hvac':id==='c'?'power':'lighting',meterParentId:id==='m'?undefined:'m',unit:'kWh'})),{id:'pie',kind:'template',name:en?'Selected end uses':'所选分项',request},{id:'own',kind:'template',name:en?'Main own usage':'总表自身',request:{...request,nodeIds:['m']}},{id:'overlap',kind:'template',name:en?'Overlapping selection':'重叠选择',request:{...request,nodeIds:['m','a']}},{id:'flow-old',kind:'template',name:en?'Existing flow':'旧能流',request:{...request,kind:'energyFlow',nodeIds:['m'],categoryId:'e'}}];
 function utility(q:ReportRequest):ReportResult{
  const amounts:Record<string,number>={m:1000,a:100,b:200,c:300},overlap=q.nodeIds.includes('m')&&q.nodeIds.length>1;
  const members=q.nodeIds.map(id=>{const r=records.find(row=>row.id===id)!;return {nodeId:id,name:r.name,utilityId:String(r.utilityId),utilityName:names[r.utilityId as keyof typeof names],categoryId:'e',unit:'kWh',value:amounts[id],quality:'ok',complete:true,coverage:1,sourceIds:[id+'-point']};});
  const total=members.reduce((s,r)=>s+r.value,0),ids=[...new Set(members.map(r=>r.utilityId))];
  const shares=ids.map(id=>{const rows=members.filter(r=>r.utilityId===id),value=rows.reduce((s,r)=>s+r.value,0);return {id,utilityId:id,name:names[id as keyof typeof names],categoryId:'e',unit:'kWh',value,quality:'ok',percentage:overlap?null:value/total*100,percentageBasis:overlap?'overlappingScopes':'knownUsage',meterIds:rows.map(r=>r.nodeId)};});
  return {kind:'utility',from:q.from,to:q.to,asOf:q.to,period:q.period,summary:{},warnings:[],rows:members.map(r=>({...r,ts:q.from})),series:members.map(r=>({id:r.nodeId,nodeId:r.nodeId,name:r.name,categoryId:'e',unit:'kWh',points:[{ts:q.from,value:r.value,quality:'ok',sourceIds:r.sourceIds}]})),extra:{utilityShares:shares,utilityMembers:members}};
 }
 function flow(q:ReportRequest):ReportResult{
  const n=(id:string,value:number,parentId?:string,extra:Partial<EnergyFlowNode>={}):EnergyFlowNode=>({id,nodeId:id,name:names[id as keyof typeof names]||id,nodeType:'meter',parentId,categoryId:'e',unit:'kWh',value,quality:'ok',sourceIds:[id+'-point'],submeter:null,difference:null,balanceQuality:'ok',hasChildren:false,percentage:null,...extra});
  const end=q.flowMode==='endUse';
  const nodes=end?[n('m',1000,undefined,{hasChildren:true,submeter:900,difference:100}),n('lighting',400,'m',{nodeType:'utility',utilityId:'lighting',memberIds:['a'],hasChildren:true}),n('power',500,'m',{nodeType:'utility',utilityId:'power',memberIds:['c'],hasChildren:true}),n('a',400,'lighting'),n('c',500,'power'),n('residual',100,'m',{nodeType:'difference'})]:[n('m',1000,undefined,{hasChildren:true}),n('a',400,'m'),n('c',500,'m')];
  const graph:EnergyFlowData={graphId:'flow-m',objectId:'m',basis:end?'endUse':'metering',categoryId:'e',unit:'kWh',focusId:'m',rootIds:['m'],nodes,links:nodes.filter(n=>n.parentId).map(n=>({source:n.parentId!,target:n.id,value:n.value!,quality:'ok',sourceIds:n.sourceIds,percentage:null,relationKind:end?'classification':'metering'})),unassigned:[],contributionMemberIds:['a','c']};
  return {kind:'energyFlow',from:q.from,to:q.to,asOf:q.to,period:'day',summary:{},warnings:[],rows:nodes.map(n=>({...n})),series:[],extra:{energyFlow:graph,energyFlowGraphs:[graph],...(end?{energyFlowAccounting:{canAdd:true,memberIds:['a','c'],sharedMemberIds:[],sharedMembers:[],unionValue:900,unionQuality:'ok',basis:'physicalBoundary'}}:{})}};
 }
 return {names,records,report:(q:ReportRequest)=>q.kind==='utility'?utility(q):flow(q)};
}
for(const language of ['zh-CN','en-US']){
 const en=language==='en-US';
 test(`shared end-use pie, own main and overlap export in ${language}`,async({page},info)=>{
  const data=setup(en),errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
  await installTransport(page,{userLocale:language,records:data.records});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>route.fulfill({json:{ok:true,data:data.report(route.request().postDataJSON())}}));
  await page.goto('/#/utility?project=testproject&template=pie');await page.getByRole('button',{name:en?'Query':'查询',exact:true}).click();
  await expect(page.locator('.utility-chart')).toHaveCount(1);await expect(page.locator('.utility-total')).toContainText('600');
  await expect(page.locator('.utility-share-table')).toContainText('50%');await expect(page.locator('.utility-member-table tr[data-row-key]')).toHaveCount(3);
  await page.locator('.utility-share-table').getByRole('button',{name:data.names.lighting,exact:true}).click();await expect(page.locator('.utility-member-table tr[data-row-key]')).toHaveCount(2);
  await page.getByRole('button',{name:en?'Show all meters':'显示全部表计',exact:true}).click();
  for(const width of [1440,390,360]){await page.setViewportSize({width,height:1000});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({fullPage:true,path:info.outputPath(`utility-${language}-${width}.png`)});}
  await page.setViewportSize({width:1440,height:1000});await page.locator('.result-toolbar').evaluate(el=>el.scrollIntoView({block:'center'}));
  await page.getByRole('button',{name:en?'Export current report':'导出当前报表'}).click();const pending=page.waitForEvent('download',{timeout:15000});await page.getByRole('menuitem',{name:/Excel/}).click();const download=await Promise.race([pending,page.locator('.ant-message-error').waitFor({state:'visible',timeout:16000}).then(async()=>{throw new Error(await page.locator('.ant-message-error').innerText());})]),path=info.outputPath('utility.xlsx');await download.saveAs(path);
  const zip=await JSZip.loadAsync(readFileSync(path)),xml=await zip.file('xl/sharedStrings.xml')!.async('string');expect(xml).toContain(en?'End-use meter details':'分项表计明细');expect(xml).toContain(data.names.a);expect(xml).toContain('300');
  if(en){await expect(page.locator('.ant-message-notice')).toHaveCount(0);await page.locator('.result-toolbar').evaluate(el=>el.scrollIntoView({block:'center'}));await page.getByRole('button',{name:'Export current report'}).click();const pdfPending=page.waitForEvent('download');await page.getByRole('menuitem',{name:/PDF/}).click();const pdf=await pdfPending,pdfPath=info.outputPath('utility.pdf');await pdf.saveAs(pdfPath);expect(readFileSync(pdfPath).length).toBeGreaterThan(10000);}
  await page.goto('/#/utility?project=testproject&template=own');await page.getByRole('button',{name:en?'Query':'查询',exact:true}).click();await expect(page.locator('.utility-total')).toContainText('1000');await expect(page.locator('.utility-member-table tr[data-row-key]')).toHaveCount(1);await expect(page.locator('.utility-member-table')).toContainText(data.names.hvac);
  await page.goto('/#/utility?project=testproject&template=overlap');await page.getByRole('button',{name:en?'Query':'查询',exact:true}).click();await expect(page.locator('.utility-group .ant-alert')).toContainText(en?'selected scopes overlap':'计量范围重叠');await expect(page.locator('.utility-chart')).toHaveCount(0);await expect(page.locator('.utility-member-table tr[data-row-key]')).toHaveCount(2);expect(errors).toEqual([]);
 });
 test(`end-use flow mode and old template compatibility in ${language}`,async({page},info)=>{
  const data=setup(en),state=await installTransport(page,{userLocale:language,records:data.records});
  await page.route('**/api/testproject/ext/enerCubix/v1/report',async route=>{const q=route.request().postDataJSON() as ReportRequest;state.requests.push({path:'report',body:q as unknown as Record<string,unknown>});await route.fulfill({json:{ok:true,data:data.report(q)}});});
  await page.goto('/#/energyFlow?project=testproject');
  await page.getByText(en?'By end use':'按能耗分项',{exact:true}).click();await page.locator('.report-dimension-select .ant-radio-button-wrapper').filter({hasText:en?'Metering':'计量'}).click();await page.locator('.object-select-button').click();
  await page.locator('.object-panel .ant-tree-treenode').filter({hasText:data.names.m}).first().locator('.ant-tree-checkbox').click();await page.locator('.object-selector-drawer .ant-drawer-footer button').click();await page.getByRole('button',{name:en?'Query':'查询',exact:true}).click();
  await expect(page.locator('.energy-flow-current')).toContainText(en?'End-use energy flow':'分项能流');await expect(page.locator('[data-flow-node="m"]')).toHaveAttribute('data-flow-value','1000');await expect(page.locator('[data-flow-node="lighting"]')).toBeVisible();expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.flowMode).toBe('endUse');
  for(const width of [1440,390,360]){await page.setViewportSize({width,height:1000});await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({fullPage:true,path:info.outputPath(`flow-${language}-${width}.png`)});}
  await page.getByRole('button',{name:en?'Save as template':'存为模板',exact:true}).click();const dialog=page.getByRole('dialog');await dialog.getByLabel(en?'Name':'名称',{exact:true}).fill(en?'End-use saved':'分项能流模板');await dialog.getByRole('button',{name:en?'Save configuration':'保存配置',exact:true}).click();await expect(dialog).toBeHidden();expect((state.records.find(r=>r.name===(en?'End-use saved':'分项能流模板'))?.request as ReportRequest).flowMode).toBe('endUse');
  await page.goto('/#/energyFlow?project=testproject&template=flow-old');await page.getByRole('button',{name:en?'Query':'查询',exact:true}).click();await expect(page.locator('.energy-flow-current')).toContainText(en?'Metering flow':'计量能流');expect(state.requests.filter(r=>r.path==='report').at(-1)?.body.flowMode).toBe('relations');
 });
}
