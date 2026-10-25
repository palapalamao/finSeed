import {describe,it,expect} from 'vitest';
import {makeSnapshot} from './exports';
import type {ReportRequest,ReportResult} from './types';

describe('ranking range snapshots',()=>{
 const request:ReportRequest={kind:'ranking',nodeIds:['a'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-24T03:00:00+08:00',period:'hour',metric:'energy',perArea:false};
 const result:ReportResult={kind:'ranking',from:'2026-10-24T01:45:00+08:00',to:'2026-10-24T02:18:20+08:00',period:'hour',rows:[],series:[],summary:{},warnings:[]};
 it('preserves requested snapshot bounds even if a legacy service adjusts its data range',()=>{
  const response={...result,rangeAdjustment:{status:'adjusted' as const,requestedFrom:request.from,requestedTo:request.to}};
  const snapshot=makeSnapshot(request,response,'ranking','cubeTest');
  expect(snapshot.request.from).toBe(request.from);expect(snapshot.request.to).toBe(request.to);
  expect(snapshot.result).toMatchObject({rangeAdjustment:{requestedFrom:request.from,requestedTo:request.to}});
  expect(request.from).toBe('2026-10-24T00:00:00+08:00');
 });
 it('preserves requested bounds when there is no common range or no adjustment',()=>{
  for(const response of [result,{...result,rangeAdjustment:{status:'unavailable' as const,requestedFrom:request.from,requestedTo:request.to}}])expect(makeSnapshot(request,response,'ranking','cubeTest').request).toEqual(request);
 });
});
