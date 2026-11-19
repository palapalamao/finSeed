import {afterEach,describe,expect,it,vi} from 'vitest';
import {makeSnapshot,reportTables} from './exports';
import {reportCellText,reportPointNames} from './reportDisplay';
import type {FinPoint,ReportRequest,ReportResult} from './types';

const request:ReportRequest={kind:'profile',nodeIds:['main'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-24T03:00:00+08:00',period:'hour',metric:'energy',perArea:false};
const points=[0,1,2].map(hour=>({ts:`2026-10-24T0${hour}:00:00+08:00`,value:null,quality:'missing',sourceIds:['p']}));
const result:ReportResult={kind:'profile',from:request.from,to:request.to,period:'hour',series:[{id:'main',name:'总电表',unit:'kWh',points}],rows:points,summary:{},warnings:['总电表 : missing','总电表: missing']};
const source:FinPoint={id:'p',name:'电能',his:true,hisStart:'2026-10-24T01:45:00+08:00',hisEnd:'2026-10-24T02:10:00+08:00'};
const snapshot=()=>makeSnapshot(request,result,'能耗概况','cubeTest',new Date('2026-10-24T02:10:57+08:00'),[],[source]);
afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});

describe('actionable report quality',()=>{
 it('replaces quality codes with readable labels in cells and nested export metadata',()=>{
  const s=snapshot();expect(reportCellText(s,'quality','missing')).toBe('历史读数不足');
  expect(reportCellText(s,'quality','ok')).toBe('正常');
  expect(reportCellText(s,'summary',{quality:'missing'})).not.toContain('missing');
  expect(reportCellText(s,'quality','futureCode')).toBe('数据异常（futureCode）');
 });
 it('explains missing boundary readings and unfinished hours in exports without changing values',()=>{
  const s=snapshot();const tables=reportTables(s);
  expect(JSON.stringify(tables.rows[0])).toContain('缺少起始读数：历史从 2026-10-24 01:45 开始');
  expect(JSON.stringify(tables.rows[2])).toContain('时段尚未结束，请在 2026-10-24 03:00 后重新查询');
  expect(JSON.stringify(tables.series)).not.toContain('missing');
  expect(s.result).toMatchObject(result);
  expect(result).not.toHaveProperty('extra');
 });
 it('keeps diagnostics tied to the saved snapshot, including a missing end reading',async()=>{
  const {reportQualityText}=await import('./reportQuality');const s=snapshot();
  expect(reportQualityText(s,'missing',points[0])).toContain('缺少起始读数');
  expect(reportQualityText(s,'missing',points[2])).toContain('时段尚未结束');
  s.generatedAt='2026-10-24T03:10:00+08:00';
  expect(reportQualityText(s,'missing',points[2])).toContain('缺少结束读数：最新历史至 2026-10-24 02:10');
 });
 it('merges duplicate service warnings and provides a practical next step',async()=>{
  const {reportWarnings}=await import('./reportQuality');const warnings=reportWarnings(snapshot());
  expect(warnings).toHaveLength(1);expect(warnings[0]).toContain('总电表');
  expect(warnings[0]).toContain('缺少起始读数');expect(warnings[0]).toContain('时段尚未结束');
  expect(warnings[0]).not.toContain('missing');
 });
 it('loads history metadata even when a native point name is already known',async()=>{
  const find=vi.fn(async()=>({items:[source]}));
  const loaded=await reportPointNames(result,[{id:'np',kind:'nativePoint',name:'电能',nativeSourceId:'p',nativeDis:'总电表 电能'}],find);
  expect(find).toHaveBeenCalledWith('p');expect(loaded[0].hisStart).toBe(source.hisStart);
 });
 it('provides the same actionable explanation in English and preserves equipment names',async()=>{
  vi.resetModules();(await import('./i18n')).initializeLocale('en-US');
  const {makeSnapshot:make}=await import('./exports');const {reportQualityText,reportWarnings}=await import('./reportQuality');
  const s=make(request,result,'Energy profile','cubeTest',new Date('2026-10-24T02:10:57+08:00'),[],[source]);
  expect(reportQualityText(s,'missing',points[0])).toContain('Missing start reading: history begins at 2026-10-24 01:45');
  expect(reportQualityText(s,'missing',points[2])).toContain('Interval not finished; query again after 2026-10-24 03:00');
  expect(reportWarnings(s)[0]).toContain('总电表');
 });
});
