import {describe,it,expect} from 'vitest';
import {initializeLocale,serverMessage} from './i18n';
describe('query read error localization',()=>{
 it('translates technical batch/catalog/alarm errors in both user languages',()=>{
  const keys=['pointBatchInvalid','catalogModeInvalid','alarmEpisodeInvalid','alarmEventUnavailable'];
  initializeLocale('zh-CN');for(const key of keys){const text=serverMessage(key);expect(text).not.toBe(key);expect(text).toMatch(/[\u4e00-\u9fff]/);}
  initializeLocale('en-US');for(const key of [...keys,'分页范围无效']){const text=serverMessage(key);expect(text).not.toBe(key);expect(text).not.toMatch(/[\u4e00-\u9fff]/);}
  initializeLocale('zh-CN');
 });
});
