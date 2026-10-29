import {afterEach,describe,expect,it,vi} from 'vitest';
import type {EnerCubixRecord} from './types';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});

describe('important change messages',()=>{
 it('preserves zero and false instead of treating them as an unset value',async()=>{
  (await import('./i18n')).initializeLocale('zh-CN');
  const {changeValue}=await import('./changeMessages');
  expect(changeValue('maximum',0,[])).toBe('0');
  expect(changeValue('includeInTotals',false,[])).toBe('关闭');
  expect(changeValue('meterParentId',null,[])).toBe('未设置');
 });
 it('resolves source and formula references while preserving business names',async()=>{
  (await import('./i18n')).initializeLocale('en-US');
  const {changeValue}=await import('./changeMessages');
  const records:EnerCubixRecord[]=[{id:'m',kind:'totalMeter',name:'地下室总电表'},{id:'a',kind:'meter',name:'照明A'}];
  expect(changeValue('meterParentId','m',records)).toBe('地下室总电表');
  expect(changeValue('variables',{input:'a'},records)).toContain('照明A');
  expect(changeValue('formula','a + b',records)).toBe('a + b');
  expect(changeValue('includeInTotals',false,records)).toBe('Off');
 });
 it('localizes category, action, fields and structured cleaning parameters',async()=>{
  (await import('./i18n')).initializeLocale('en-US');
  const {changeCategoryLabel,changeActionLabel,changeFieldLabel,changeValue}=await import('./changeMessages');
  expect(changeCategoryLabel('relationship')).toBe('Relationship change');
  expect(changeActionLabel('updated')).toBe('Updated');
  expect(changeFieldLabel('meterParentId')).toBe('Parent meter');
  expect(changeValue('parameters',{deltaMax:50},[])).toContain('50');
  expect(changeValue('parameters',{deltaMax:50},[])).not.toContain('undefined');
 });
});
