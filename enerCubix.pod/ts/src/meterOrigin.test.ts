import {describe,expect,it} from 'vitest';
import {meterOrigin} from './meterOrigin';
import {buildReportDisplay,profileGroups} from './reportDisplay';
import {meterOriginExportRows} from './exports';
import type {EnerCubixRecord,ReportSnapshot} from './types';

describe('meter origin in report snapshots',()=>{
 it('preserves source metadata without renaming meters or changing calculations',()=>{
  const records:EnerCubixRecord[]=[{id:'main',name:'Business meter',kind:'totalMeter',autoSum:true},{id:'physical',name:'真实设备',kind:'totalMeter',meterOrigin:{type:'physical',reason:'connector',protocol:'modbus',pointId:'p',connectorId:'c'}}];
  const before=structuredClone(records),display=buildReportDisplay(records);
  expect(display.objects.main).toBe('Business meter');expect(display.meterOrigins?.main.type).toBe('virtual');
  expect(display.meterOrigins?.physical).toEqual(records[1].meterOrigin);expect(records).toEqual(before);
  const request={kind:'profile',nodeIds:['main'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-25T00:00:00+08:00',period:'day',metric:'energy',perArea:false} as const;
  const snapshot:ReportSnapshot={title:'Profile',project:'cubeTest',generatedAt:request.to,request:{...request,nodeIds:['main']},display,result:{kind:'profile',from:request.from,to:request.to,period:'day',series:[{id:'main',nodeId:'main',name:'Business meter',unit:'kWh',points:[{ts:request.from,value:25,quality:'ok',sourceIds:['p']}]}],summary:{total:25},warnings:[],rows:[]}};
  const saved=structuredClone(snapshot),groups=profileGroups(snapshot);
  expect(groups[0].series[0].name).toContain('虚拟总表');expect(snapshot).toEqual(saved);
  const exportRows=meterOriginExportRows(snapshot);expect(exportRows).toHaveLength(1);expect(exportRows[0][1]).toContain('Business meter：虚拟总表');
  expect(structuredClone(snapshot).display?.meterOrigins).toEqual(display.meterOrigins);
 });
 it('uses configured generation before any older display metadata',()=>{
  expect(meterOrigin({kind:'totalMeter',autoSum:true,meterOrigin:{type:'physical',reason:'connector'}})).toEqual({type:'virtual',reason:'submeterSum'});
  expect(meterOrigin({kind:'totalMeter',expressionId:'formula'})).toEqual({type:'virtual',reason:'expression'});
  expect(meterOrigin({kind:'totalMeter',historyPointId:'derived',pointId:'p'}).type).toBe('unconfirmed');
 });
});
