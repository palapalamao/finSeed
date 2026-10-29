// Test-only transport fixture. Production code always calls authenticated FIN APIs.
import {expect,type Page,type Route} from '@playwright/test';
import type {ReportRequest,ReportResult,EnerCubixRecord} from '../../src/types';
import {dimensionBranch,dimensionPath,relationField} from '../../src/dimensionTree';
import type {Dimension} from '../../src/types';
import type {MigrationPreview} from '../../src/api';
export function testRecords():EnerCubixRecord[]{return [
 {id:'g1',mod:'m1',kind:'group',name:'测试建筑',area:100},
 {id:'cat1',mod:'m1',kind:'category',name:'测试电力',unit:'kWh'},
 {id:'sub1',mod:'m1',kind:'subcategory',name:'测试子类',categoryId:'cat1',coalFactor:.1,co2Factor:.2},
 {id:'utility1',mod:'m1',kind:'utility',name:'测试照明',categoryId:'cat1'},
 {id:'meter1',mod:'m1',kind:'meter',name:'测试分表',parentId:'g1',pointId:'point1',unit:'kWh',categoryId:'cat1',subcategoryId:'sub1',utilityId:'utility1',includeInTotals:true},
 {id:'master1',mod:'m1',kind:'totalMeter',name:'测试总表',parentId:'g1',pointId:'point2',unit:'kWh',categoryId:'cat1',includeInTotals:true},
 {id:'sensor1',mod:'m1',kind:'sensor',name:'测试传感器',parentId:'g1',pointId:'point3',unit:'°C'},
 {id:'cop1',mod:'m1',kind:'cop',name:'测试COP',numeratorId:'g1',denominatorId:'meter1'},
 {id:'tariff1',mod:'m1',kind:'tariff',name:'测试费率',mode:'flat',rate:1,categoryId:'cat1',isDefault:true,rules:[],exceptions:[],blocks:[]},
 {id:'calendar1',mod:'m1',kind:'calendar',name:'测试日历',isDefault:true,peakHours:[],valleyHours:[],workDays:[1,2,3,4,5],workHours:[8,9,10,11,13,14,15,16,17],exceptions:[]},
 {id:'expression1',mod:'m1',kind:'expression',name:'测试公式',formula:'a * 2',variables:{a:'meter1'}},
 {id:'template1',mod:'m1',kind:'template',name:'测试上月模板',preset:'lastMonth',request:{kind:'profile',nodeIds:['meter1'],from:'2000-01-01T00:00:00+08:00',to:'2000-02-01T00:00:00+08:00',metric:'energy',period:'day',perArea:false}},
 {id:'settings1',mod:'m1',kind:'settings',name:'概览设置',rotationSeconds:20,visibleMetrics:['energy','cost','coal','co2']}
];}
export function resultFor(request:ReportRequest,missing=false):ReportResult{
 if(request.kind==='forecast'){
  const history={ts:request.from,value:12,quality:'ok',sourceIds:['point1']};const count=request.forecastDays||7;
  const points=Array.from({length:count},(_,i)=>({ts:new Date(Date.parse(request.to)+i*86400000).toISOString(),value:missing?null:10,lower:8,upper:12,quality:'predicted',sourceIds:['point1']}));
  return {kind:'forecast',from:request.from,to:request.to,period:'day',series:[{id:'meter1|history',nodeId:'meter1',name:'测试分表 · 历史',categoryId:'cat1',unit:'kWh',role:'history',points:[history]},...(!missing?[{id:'meter1|forecast',nodeId:'meter1',name:'测试分表 · 预测',categoryId:'cat1',unit:'kWh',role:'forecast' as const,points}]:[])],rows:[{...history,name:'测试分表',categoryId:'cat1',phase:'history',unit:'kWh'},...(!missing?points.map(p=>({...p,name:'测试分表',categoryId:'cat1',phase:'forecast',unit:'kWh'})):[])],summary:{},warnings:['测试模拟历史，不能代表真实运行预测能力'],extra:{forecasts:[{id:'meter1',nodeId:'meter1',name:'测试分表',categoryId:'cat1',unit:'kWh',status:missing?'insufficientHistory':'ok',predictedTotal:missing?null:count*10,model:'weekdayMean',mae:1,wape:5,baselineMae:2,validDays:50,trainingDays:56,backtestDays:28,simulated:true}],modelScores:[],backtests:[]}};
 }
 const value=missing?null:12;const point={ts:request.from,value,quality:missing?'missing':'ok',sourceIds:['point1']};
 const row={key:'fixture-row',name:'测试分表',categoryId:'cat1',value,unit:'kWh',quality:point.quality,sourceIds:['point1'],...(request.kind==='regression'?{x:2,y:12}:{}),...(['workingHours','workingDays'].includes(request.kind)?{working:8,nonworking:4}:{}),...(['proportion','ranking'].includes(request.kind)?{rank:1,percentage:100}:{})};
 return {kind:request.kind,from:request.from,to:request.to,period:request.period,series:[{id:'meter1',name:'测试分表',unit:'kWh',categoryId:'cat1',points:[point]}],rows:[row],summary:{totals:[{id:'meter1',name:'测试分表',categoryId:'cat1',value,unit:'kWh',quality:point.quality}]},warnings:missing?['测试源点历史读取失败，结果保持缺测']:[],extra:request.kind==='regression'?{slope:6,intercept:0,r2:1}:request.kind==='dashboard'||request.kind==='comparison'?{comparisons:[{id:'meter1',name:'测试分表',current:12,reference:10,difference:2,percentage:20}]}:{}};
}
export interface TransportState {userLocale:string;username:string;records:EnerCubixRecord[];requests:{path:string;body:Record<string,unknown>}[];canWrite:boolean;status:number;missing:boolean;alarms:EnerCubixRecord[];migrationPreview?:MigrationPreview;spaceSource?:'fin';storageModel?:'nativeEquip';report?:(request:ReportRequest)=>ReportResult}
export async function installTransport(page:Page,options:Partial<TransportState>={}){
 const state:TransportState={username:'test-user',userLocale:await page.evaluate(()=>navigator.language),records:testRecords(),requests:[],canWrite:true,status:200,missing:false,alarms:[{id:'alarm1',mod:'m1',kind:'alarm',name:'测试超限',nodeId:'meter1',categoryId:'cat1',ts:'2026-10-20T00:00:00+08:00',value:20,limit:10,state:'open'}],...options};
 await page.route('**/finStackAuth',route=>route.fulfill({status:200,headers:{'fin-stack-auth':'test-only-attest'},body:''}));
 await page.route('**/api/testproject/ext/enerCubix/v1/**',async route=>{
  const request=route.request();const path=new URL(request.url()).pathname.split('/v1/')[1];const body=request.method()==='POST'?request.postDataJSON():{};state.requests.push({path,body});
  const reply=(data:unknown)=>route.fulfill({status:200,json:{ok:true,data}});const fail=(status:number,msg:string)=>route.fulfill({status,json:{ok:false,error:{code:status===401?'unauthorized':'forbidden',msg}}});
  if(state.status!==200)return fail(state.status,state.status===401?'FIN 会话已过期，请在 FIN 中重新登录。':'当前 FIN 用户没有项目管理权限');
  if(request.method()==='POST'&&!state.canWrite&&path!=='report')return fail(403,'当前 FIN 用户没有项目管理权限');
  if(path==='session')return reply({locale:state.userLocale,username:state.username});
  if(path==='catalog')return reply({version:'0.1-test-transport',project:'testproject',storageModel:state.storageModel,...(state.spaceSource?{spaceSource:state.spaceSource}:{}),user:{name:'测试会话',canWrite:state.canWrite},records:state.records});
  if(path==='migration/preview')return reply(state.migrationPreview||{version:1,revision:JSON.stringify(state.records),sourceRevision:'native1',records:[],suggestions:[],warnings:[],counts:{added:0,updated:0,canonicalAliases:0,spaces:0,suggestions:0,unboundMeters:0}});
  if(path==='migration'){const preview=state.migrationPreview;if(body.action==='apply'&&preview){const accepted=(body.acceptedSuggestionIds||[])as string[];const added=[...preview.records,...preview.suggestions.filter(row=>accepted.includes(row.id)).flatMap(row=>row.records)].map(row=>({...row,mod:'migrated'}));state.records=state.records.filter(row=>!added.some(item=>item.id===row.id)).concat(added);const placements=body.placements as Record<string,string>||{};for(const suggestion of preview.suggestions)if(accepted.includes(suggestion.id)&&placements[suggestion.id])state.records=state.records.map(row=>suggestion.recordIds.includes(row.id!)?{...row,spaceId:placements[suggestion.id]}:row);const job:EnerCubixRecord={id:'migrationJob',mod:'jobmod',kind:'job',name:'三树迁移',action:'treeMigration',status:'applied'};state.records.push(job);return reply({job,applied:added.length});}return reply({job:null,applied:0});}
  if(path==='report')return reply(state.report?state.report(body as ReportRequest):resultFor(body as ReportRequest,state.missing));
  if(path==='points')return reply({items:[{id:'point1',name:'测试源点一',unit:'kWh',kind:'Number',his:true,hisMode:'cumulative'},{id:'point2',name:'测试源点二',unit:'kWh',kind:'Number',his:true},{id:'point3',name:'测试源点三',unit:'°C',kind:'Number',his:true}],total:3,offset:0,limit:100});
  if(path==='records'){const input=body.record as EnerCubixRecord;const saved={...input,id:input.id||`saved${state.records.length}`,mod:`m${state.requests.length}`};state.records=state.records.filter(record=>record.id!==saved.id).concat(saved);return reply(saved);}
  if(path==='records/delete'){state.records=state.records.filter(record=>record.id!==body.id);return reply({deleted:body.id});}
  if(path==='tree/manage'){
   const items=(body.items||[])as EnerCubixRecord[];const ids=items.map(r=>r.id!);const action=String(body.action);
   if(action==='save'){const input=body.records as EnerCubixRecord[];const added=input.map((r,i)=>({...r,id:r.id||`batch${state.requests.length}-${i}`,mod:`m${state.requests.length}`}));state.records=state.records.filter(r=>!added.some(a=>a.id===r.id)).concat(added);return reply({records:added});}
   const dimension=(body.dimension||'legacy')as Dimension;
   if(action==='assign'){const patch=body.patch as Record<string,unknown>;state.records=state.records.map(row=>ids.includes(row.id!)?{...row,...patch,mod:`m${state.requests.length}`}:row);return reply({records:state.records.filter(row=>ids.includes(row.id!))});}
   if(action==='move'){if(ids.some(id=>dimensionBranch(state.records,id,dimension).has(String(body.parentId))))return fail(400,'管理树不能形成循环');const roots=ids.filter(id=>!dimensionPath(state.records,id,dimension).slice(0,-1).some(r=>ids.includes(r.id!)));state.records=state.records.map(r=>roots.includes(r.id!)?{...r,[relationField(r,dimension)]:body.parentId,mod:`m${state.requests.length}`}:r);return reply({records:state.records.filter(r=>roots.includes(r.id!))});}
   if(action==='copy')return reply({records:state.records});
   if(action==='totals'){state.records=state.records.map(r=>ids.includes(r.id!)?{...r,includeInTotals:body.included,mod:`m${state.requests.length}`}:r);return reply({records:state.records.filter(r=>ids.includes(r.id!))});}
   const selected=new Set(ids.flatMap(id=>[...dimensionBranch(state.records,id,dimension)].filter(child=>child===id||dimension==='legacy'||dimension==='metering'||state.records.find(row=>row.id===child)?.kind===dimension))); const contains=(value:unknown):boolean=>typeof value==='string'?selected.has(value):Array.isArray(value)?value.some(contains):!!value&&typeof value==='object'&&Object.entries(value).some(([key,v])=>key!=='id'&&key!=='mod'&&contains(v));
   const rows=state.records.filter(r=>selected.has(r.id!));const blockers=state.records.filter(r=>!selected.has(r.id!)&&!['alarm','job'].includes(r.kind)&&contains(r));
   const revision=JSON.stringify(state.records);if(action==='previewDelete')return reply({revision,records:rows,blockers});
   if(action==='delete'){if(body.revision!==revision)return fail(409,'配置已变化，请重新查看删除预览');if(blockers.length)return fail(400,'仍被外部配置引用');state.records=state.records.filter(r=>!selected.has(r.id!));return reply({deleted:[...selected]});}
  }
  if(path==='tree/copy'||path==='tree/move')return reply({records:state.records});
  if(path==='alarms')return reply(state.alarms);
  if(path==='alarms/ack'){const alarm={...state.alarms[0],state:'acknowledged',ackBy:'测试会话',ackAt:new Date().toISOString(),ackNote:body.note};state.alarms=[alarm];return reply(alarm);}
  if(path==='tasks'){const job:EnerCubixRecord={id:`job${state.requests.length}`,mod:'m1',kind:'job',name:`测试任务 ${body.action}`,action:body.action,enabled:body.enabled,status:'complete',processed:1,lastRun:new Date().toISOString()};state.records.push(job);return reply(job);}
  await route.fulfill({status:404,json:{ok:false,error:{code:'fixture_unhandled',msg:path}}});
 });
 return state;
}
export async function openView(page:Page,view:string){await page.goto(`/#/${view}?project=testproject`);await expect(page.locator('.content-frame')).toBeVisible();}
export async function openObjects(page:Page){if(!await page.locator('.object-panel').isVisible())await page.locator('.object-select-button').click();await expect(page.locator('.object-panel')).toBeVisible();}
export async function closeObjects(page:Page){if(await page.locator('.object-selector-drawer.ant-drawer-open').count())await page.locator('.object-selector-drawer .ant-drawer-footer .ant-btn').click();await expect(page.locator('.object-panel')).toBeHidden();}
export async function openMoreFilters(page:Page){if(!await page.locator('.advanced-query-fields').isVisible())await page.locator('.filter-actions .ant-btn').last().click();await expect(page.locator('.advanced-query-fields')).toBeVisible();}
export async function closeMoreFilters(page:Page){if(await page.locator('.advanced-query-drawer.ant-drawer-open').count())await page.locator('.advanced-query-drawer .ant-drawer-footer .ant-btn').click();await expect(page.locator('.advanced-query-fields')).toBeHidden();}
export async function checkNode(page:Page,name='测试分表'){await openObjects(page);const node=page.locator('.object-panel .ant-tree-treenode').filter({hasText:name});await node.locator('.ant-tree-checkbox').click();await closeObjects(page);}
export async function query(page:Page){await closeObjects(page);await closeMoreFilters(page);await page.getByRole('button',{name:/查\s*询/}).click();await expect(page.getByRole('button',{name:'导出当前报表'})).toBeVisible();await expect(page.locator('.report-chart canvas').first()).toBeVisible();}
