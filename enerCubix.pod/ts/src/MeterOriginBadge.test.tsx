import {afterEach,beforeAll,describe,expect,it,vi} from 'vitest';
import type {EnerCubixRecord} from './types';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});
beforeAll(async()=>{await import('./MeterOriginBadge');},30000);
async function render(record:EnerCubixRecord,language='zh-CN'){
 vi.resetModules();vi.stubGlobal('navigator',{language,languages:[language]});
 const [{createElement},{renderToStaticMarkup},{MeterOriginBadge}]=await Promise.all([import('react'),import('react-dom/server'),import('./MeterOriginBadge')]);
 return renderToStaticMarkup(createElement(MeterOriginBadge,{record}));
}
describe('meter origin badge',()=>{
 it.each(['zh-CN','en-US'])('distinguishes physical and virtual totals with visible labels and icons in %s',async language=>{
  const physical=await render({kind:'totalMeter',name:'用户原名',meterOrigin:{type:'physical',reason:'connector',protocol:'modbus'}},language);
  const virtual=await render({kind:'totalMeter',name:'用户原名',autoSum:true,meterOrigin:{type:'physical',reason:'connector'}},language);
  expect(physical).toContain(language==='zh-CN'?'物理总表':'pTotal Meter');
  expect(virtual).toContain(language==='zh-CN'?'虚拟总表':'vTotal Meter');
  expect(physical).toContain('data-icon="dashboard"');expect(virtual).toContain('data-icon="calculator"');
 });
 it('keeps unavailable evidence distinct from a physical source',async()=>{
  const record:EnerCubixRecord={kind:'totalMeter',name:'原名',pointId:'p',historyPointId:'computed'},before=structuredClone(record);
  const html=await render(record);
  expect(html).toContain('来源待确认');expect(html).toContain('data-icon="question-circle"');expect(record).toEqual(before);
 });
 it('recognizes formulas and leaves ordinary assets undecorated',async()=>{
  expect(await render({kind:'totalMeter',name:'公式',expressionId:'f'})).toContain('虚拟总表');
  expect(await render({kind:'space',name:'空间'})).toBe('');
 });
});
