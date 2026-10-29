import {afterEach,describe,expect,it,vi} from 'vitest';
import {readFileSync,readdirSync} from 'node:fs';
import ts from 'typescript';
import {englishMessages} from './messages';
import {serverMessages} from './serverMessages';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});

describe('FIN user interface language',()=>{
 it.each(['zh','zh-CN','zh-TW','zh-HK','zh-Hans','zh-Hant','ZH-cn'])('uses Chinese for FIN locale %s',async language=>{
  const {resolveFinLocale}=await import('./i18n');
  expect(resolveFinLocale(language)).toBe('zh-CN');
 });
 it.each(['en-US','en-GB','fr-FR','de-DE','ja-JP',''])('defaults to English for unsupported FIN locale %s',async language=>{
  const {resolveFinLocale}=await import('./i18n');
  expect(resolveFinLocale(language)).toBe('en-US');
 });
 it('translates placeholders without translating inserted project data',async()=>{
  (await import('./i18n')).initializeLocale('en-US');
  const {t}=await import('./i18n');
  expect(t('编辑{0}','能源概览')).toBe('Edit 能源概览');
  expect(t('共 {0} 条',12)).toBe('12 records');
  expect(t('回归方程：Y = {0}',6)).toBe('Regression equation: Y = 6');
  expect(t('Unrecognized server detail')).toBe('Unrecognized server detail');
 });
 it('preserves Chinese text and substitutions',async()=>{
  (await import('./i18n')).initializeLocale('zh-CN');
  const {t,locale}=await import('./i18n');
  expect(locale).toBe('zh-CN');
  expect(t('共 {0} 条',12)).toBe('共 12 条');
  expect(t('回归方程：Y = {0}',6)).toBe('回归方程：Y = 6');
 });
 it('uses the same locale for shared labels, charts and export headers',async()=>{
  (await import('./i18n')).initializeLocale('en-US');
  const {reportNames}=await import('./types');
  const {loadBandNames}=await import('./chartOptions');
  const {reportLabels,compactReportTime,displaySeriesName}=await import('./reportDisplay');
  expect(reportNames.dashboard).toBe('Energy overview');
  expect(loadBandNames.peak).toBe('Peak');
  expect(reportLabels.sourceIds).toBe('Source points');
  expect(compactReportTime('2026-10-12T00:00:00+08:00','month')).toBe('2026/10');
  expect(compactReportTime('2026-10-12T00:00:00+08:00','year')).toBe('2026');
  expect(displaySeriesName({id:'a',name:'能源概览 · 预测',role:'forecast',unit:'kWh',points:[]})).toBe('能源概览 · Forecast');
  expect(displaySeriesName({id:'a',name:'能源概览',unit:'kWh',points:[]})).toBe('能源概览');
 });
 it('sets the document language, title and date locale together',async()=>{
  (await import('./i18n')).initializeLocale('en-US');
  vi.stubGlobal('document',{documentElement:{lang:''},title:''});
  const {initializeLocale}=await import('./i18n');
  const {default:dayjs}=await import('dayjs');
  initializeLocale('en-US');expect(document.documentElement.lang).toBe('en-US');
  expect(document.title).toBe('EnergyCubix · Building Energy Analytics');expect(dayjs.locale()).toBe('en');
 });
 it.each([
  ['zh-CN','能源魔方','楼宇能源分析'],
  ['en-US','EnergyCubix','Building Energy Analytics'],
  ['fr-FR','EnergyCubix','Building Energy Analytics']
 ])('uses the localized product lockup for %s',async(language,name,tagline)=>{
  (await import('./i18n')).initializeLocale(language);
  const {productName,productTagline}=await import('./brand');
  expect(productName).toBe(name);expect(productTagline).toBe(tagline);
 });
 it('translates known service warnings without translating captured names',async()=>{
  (await import('./i18n')).initializeLocale('en-US');
  const {serverMessage}=await import('./i18n');
  expect(serverMessage('能源概览: 分项覆盖不完整')).toBe('能源概览: End-use coverage is incomplete.');
  expect(serverMessage('名称已存在')).toBe('Name already exists');
  expect(serverMessage('核实空间：能源概览')).toBe('Verify space: 能源概览');
  expect(serverMessage('确认“能源概览”的 3 块分表上级')).toBe('Confirm the parent for 3 submeters in “能源概览”');
  expect(serverMessage('能源概览：有效历史不足，至少需要 28 个有效日、80% 完整率和最近 7 天完整数据；长周期预测还需要足够的历史回测范围')).toContain('能源概览: Insufficient valid history.');
  expect(serverMessage('Unknown technical detail')).toBe('Unknown technical detail');
 });
 it.each(['zh-CN','en-US'])('translates virtual cleaning blockers in %s while preserving meter names',async language=>{
  (await import('./i18n')).initializeLocale(language);
  const {serverMessage}=await import('./i18n');
  const source='虚拟总表“总表 A”无法保存清洗配置，请先处理以下问题：\n“名称已存在”：尚未启用清洗或未选择清洗方案\n“B”：主能耗点单位与上级总表不兼容';
  expect(serverMessage(source)).toBe(language==='zh-CN'?source:'Cannot save cleaning for virtual main meter “总表 A”. Resolve these issues first:\n“名称已存在”: Cleaning is not enabled or no cleaning profile is selected.\n“B”: The main energy point unit is incompatible with the parent meter.');
 });
 it('has English translations for every application text key and preserves placeholders',()=>{
  const missing:string[]=[];
  const directory=new URL('.',import.meta.url);
  for(const filename of readdirSync(directory).filter(file=>/\.tsx?$/.test(file)&&!/(?:\.test\.|i18n|messages|serverMessages)/.test(file))){
   const source=ts.createSourceFile(filename,readFileSync(new URL(filename,directory),'utf8'),ts.ScriptTarget.Latest,true);
   const visit=(node:ts.Node)=>{
    if(ts.isCallExpression(node)&&ts.isIdentifier(node.expression)&&node.expression.text==='t'&&node.arguments[0]&&ts.isStringLiteral(node.arguments[0])){
     const key=node.arguments[0].text;if(/\p{Script=Han}/u.test(key)&&!(key in englishMessages)&&!(key in serverMessages))missing.push(filename+': '+key);
    }
    ts.forEachChild(node,visit);
   };visit(source);
  }
  expect(missing).toEqual([]);
  const placeholders=(text:string)=>[...text.matchAll(/\{\d+\}/g)].map(match=>match[0]).sort();
  for(const [key,value] of Object.entries({...englishMessages,...serverMessages})){
   expect(value.trim(),key).not.toBe('');expect(value,key).not.toMatch(/\p{Script=Han}/u);
   expect(placeholders(value),key).toEqual(placeholders(key));
  }
 });
});
