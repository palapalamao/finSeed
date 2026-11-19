import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import JSZip from 'jszip';
import {installTransport,openView,testRecords} from './fixtures';
import type {FinEnergyRecord,ReportRequest,ReportResult} from '../../src/types';

// Controlled transport verifies the shipped UI and downloaded files, not FIN persistence.
for(const language of ['zh-CN','en-US'])for(const mobile of [false,true])test(`service area editing and frozen report ${language} ${mobile?'mobile':'desktop'}`,async({page},info)=>{
 page.setDefaultTimeout(10000);const zh=language==='zh-CN';await page.setViewportSize(mobile?{width:390,height:844}:{width:1440,height:1000});
 const records:FinEnergyRecord[]=[...testRecords().filter(row=>!['g1','master1'].includes(String(row.id))).map(row=>row.id==='meter1'?{...row,name:'Lighting',nativeEquip:true,nativeName:'Lighting',parentId:undefined,nativeSourceKind:'equip',spaceId:'floor',area:800}:row),{id:'site',kind:'space',name:'Campus',nativeReadonly:true,nativeSourceKind:'site',nativeSourceId:'site',mod:'site-mod',area:3000},{id:'floor',kind:'space',name:'1F',parentId:'site',nativeReadonly:true,nativeSourceKind:'floor',nativeSourceId:'floor',area:1000},{id:'area-template',kind:'template',name:'Area report',preset:'lastMonth',request:{kind:'profile',dimension:'metering',nodeIds:['meter1'],metric:'energy',period:'day',perArea:true}}];
 const report=(q:ReportRequest):ReportResult=>({kind:q.kind,from:q.from,to:q.to,period:q.period,warnings:[],summary:{},series:[{id:'meter1|cat1',nodeId:'meter1',name:'Lighting',categoryId:'cat1',unit:'kWh/m²',points:[{ts:q.from,value:0.3,quality:'ok',sourceIds:['point1']}]}],rows:[{nodeId:'meter1',name:'Lighting',categoryId:'cat1',value:0.3,unit:'kWh/m²'}],extra:{areaBasis:[{nodeId:'meter1',name:'Lighting',categoryId:'cat1',baseValue:300,baseUnit:'kWh',value:0.3,unit:'kWh/m²',area:{value:1000,quality:'ok',unit:'m²',sources:[{id:'floor',name:'1F',area:1000,source:'space'}]}}]}});
 const state=await installTransport(page,{records,spaceSource:'fin',storageModel:'nativeEquip',userLocale:language,report});
 let areaPayload:Record<string,unknown>|undefined;
 await page.route('**/api/*/ext/finEnergy/v1/records',async route=>{
  const body=route.request().postDataJSON(),row=body.record;
  if(!row?.areaOnly)return route.fallback();
  areaPayload=row;state.records=state.records.map(old=>old.id===row.id?{...old,area:row.area,mod:'saved-area'}:old);
  await route.fulfill({json:{ok:true,data:state.records.find(old=>old.id===row.id)}});
 });
 await openView(page,'tree');
 await page.getByRole('button',{name:zh?'编辑面积':'Edit area',exact:true}).first().click();
 const areaEditor=page.getByRole('dialog',{name:zh?'编辑空间面积：Campus':'Edit space area: Campus'});
 await areaEditor.getByRole('spinbutton',{name:zh?'建筑面积 (m²)':'Building area (m²)',exact:true}).fill('3500');
 await expect(areaEditor.getByRole('textbox')).toHaveCount(0);
 await areaEditor.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();await expect(areaEditor).toBeHidden();
 expect(areaPayload).toEqual({id:'site',mod:'site-mod',kind:'space',areaOnly:true,area:3500});
 await page.locator('.dimension-switch').getByText(zh?'计量':'Metering',{exact:true}).click();
 await page.getByRole('radiogroup',{name:zh?'显示范围':'Display scope'}).getByText(zh?'全部对象':'All objects',{exact:true}).click();
 await page.locator('.meter-object-table').getByRole('button',{name:(zh?'编辑':'Edit')+'Lighting',exact:true}).click();
 const editor=page.locator('.ant-drawer-open').filter({has:page.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true})});
 await editor.getByRole('combobox',{name:zh?'面积来源':'Area source',exact:true}).press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText(zh?'引用服务空间面积':'Use a service space area',{exact:true}).click();
 await editor.getByRole('combobox',{name:zh?/服务空间/:/Service space/}).press('ArrowDown');
 await page.locator('.ant-select-dropdown:visible').getByText('Campus / 1F',{exact:true}).click();
 await expect(editor).toContainText(zh?'当前面积：1000 m²':'Current area: 1000 m²');
 await editor.getByRole('button',{name:zh?'保存配置':'Save configuration',exact:true}).click();await expect(editor).toBeHidden();
 const saved=state.requests.filter(row=>row.path==='records').at(-1)?.body.record as FinEnergyRecord;
 expect(saved.areaSource).toBe('space');expect(saved.areaSpaceId).toBe('floor');
 await page.goto('/#/profile?project=testproject&template=area-template');await page.getByRole('button',{name:zh?'查询':'Query',exact:true}).click();
 await expect(page.locator('.area-basis')).toContainText('300 kWh ÷ 1,000 m² = 0.3 kWh/m²');await expect(page.locator('.area-basis')).toContainText('1F');
 state.records=state.records.map(row=>row.id==='floor'?{...row,name:'Changed later',area:9999}:row);
 await expect(page.locator('.ant-message-notice')).toHaveCount(0);
 await page.getByRole('button',{name:zh?'导出当前报表':'Export current report'}).click();const download=page.waitForEvent('download');await page.getByRole('menuitem',{name:zh?'Excel 工作簿 (.xlsx)':'Excel workbook (.xlsx)',exact:true}).click();
 const zip=await JSZip.loadAsync(await readFile((await (await download).path())!));const text=await zip.file('xl/sharedStrings.xml')!.async('string');
 expect(text).toContain('300 kWh ÷ 1,000 m² = 0.3 kWh/m²');expect(text).toContain('1F');expect(text).not.toContain('Changed later');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(mobile?390:1440);
 await page.screenshot({path:info.outputPath('area-report.png'),fullPage:true});
});
