import {describe,expect,it} from 'vitest';
import {reportDimension,reportNames,type ReportSnapshot} from './types';
import {analysisGroups} from './navigation';
import {makeSnapshot,reportTables} from './exports';
import dayjs from 'dayjs';
import {energyFlowRange} from './dates';
describe('energy-flow workspace contract',()=>{
 it('defaults to month to date without changing complete past-month ranges',()=>{
  const now=dayjs('2026-10-23T12:00:00+08:00');
  expect(energyFlowRange('thisMonth',now)[1].valueOf()).toBe(now.valueOf());
  expect(energyFlowRange('lastMonth',now).map(date=>date.format('YYYY-MM-DD'))).toEqual(['2026-09-01','2026-10-01']);
 });
 it('locks metering scope and exposes energy flow under composition',()=>{
  expect(reportDimension('energyFlow','space')).toBe('metering');
  expect(analysisGroups.find(group=>group.key==='structure')?.kinds).toContain('energyFlow');
  expect(reportNames.energyFlow).toBeDefined();
 });
 it('localizes synthetic nodes for exports without translating business names',()=>{
  const rows=[{id:'main',nodeId:'main',nodeType:'meter',name:'业务总表',value:100},{id:'diff',nodeId:'diff',nodeType:'difference',name:'',value:10},{id:'sum',nodeId:'sum',nodeType:'summary',name:'电',value:100}];
  const snapshot=makeSnapshot({kind:'energyFlow',dimension:'metering',nodeIds:[],categoryId:'electric',from:'2026-10-01T00:00:00Z',to:'2026-10-02T00:00:00Z',period:'day',metric:'energy',perArea:false},{kind:'energyFlow',from:'2026-10-01T00:00:00Z',to:'2026-10-02T00:00:00Z',period:'day',series:[],rows,warnings:[],summary:{},extra:{energyFlow:{nodes:rows,links:[],rootIds:['main'],focusId:'sum',categoryId:'electric',unit:'kWh',unassigned:[]}}},'Energy flow','test');
  expect(snapshot.result.rows[0].name).toBe('业务总表');
  expect(snapshot.result.rows[1].name).not.toBe('');
  expect(reportTables(snapshot as ReportSnapshot).rows.flat()).toContain(snapshot.result.rows[1].name);
 });
});
