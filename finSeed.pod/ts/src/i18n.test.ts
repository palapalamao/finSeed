import {afterEach,describe,expect,it,vi} from 'vitest';
import {readFileSync,readdirSync} from 'node:fs';
import ts from 'typescript';
import {englishMessages} from './messages';
import {serverMessages} from './serverMessages';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});

describe('automatic interface language',()=>{
 it.each(['zh','zh-CN','zh-TW','zh-HK','zh-Hans','zh-Hant','ZH-cn'])('uses Chinese for %s',async language=>{
  const {detectLocale}=await import('./i18n');
  expect(detectLocale({language,languages:[language]})).toBe('zh-CN');
 });
 it.each(['en-US','en-GB','fr-FR','de-DE','ja-JP',''])('defaults to English for %s',async language=>{
  const {detectLocale}=await import('./i18n');
  expect(detectLocale({language,languages:[]})).toBe('en-US');
 });
 it('uses the first browser preference, with language-list and system fallbacks',async()=>{
  const {detectLocale}=await import('./i18n');
  expect(detectLocale({language:'en-US',languages:['en-US','zh-CN']})).toBe('en-US');
  expect(detectLocale({languages:['zh-TW','en-US']})).toBe('zh-CN');
  expect(detectLocale({},'zh-CN')).toBe('zh-CN');
  expect(detectLocale({},'fr-FR')).toBe('en-US');
 });
 it('translates placeholders without translating inserted project data',async()=>{
  vi.stubGlobal('navigator',{language:'en-US'});
  const {t}=await import('./i18n');
  expect(t('编辑{0}','能源概览')).toBe('Edit 能源概览');
  expect(t('共 {0} 条',12)).toBe('12 records');
  expect(t('回归方程：Y = {0}',6)).toBe('Regression equation: Y = 6');
  expect(t('Unrecognized server detail')).toBe('Unrecognized server detail');
 });
 it('preserves Chinese text and substitutions',async()=>{
  vi.stubGlobal('navigator',{language:'zh-CN'});
  const {t,locale}=await import('./i18n');
  expect(locale).toBe('zh-CN');
  expect(t('共 {0} 条',12)).toBe('共 12 条');
  expect(t('回归方程：Y = {0}',6)).toBe('回归方程：Y = 6');
 });
 it('uses the same locale for shared labels, charts and export headers',async()=>{
  vi.stubGlobal('navigator',{language:'en-US'});
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
  vi.stubGlobal('navigator',{language:'en-US'});
  vi.stubGlobal('document',{documentElement:{lang:''},title:''});
  const {initializeLocale}=await import('./i18n');
  const {default:dayjs}=await import('dayjs');
  initializeLocale();expect(document.documentElement.lang).toBe('en-US');
  expect(document.title).toBe('EnerCubix · Multidimensional Energy Analytics');expect(dayjs.locale()).toBe('en');
 });
 it('translates known service warnings without translating captured names',async()=>{
  vi.stubGlobal('navigator',{language:'en-US'});
  const {serverMessage}=await import('./i18n');
  expect(serverMessage('能源概览: 分项覆盖不完整')).toBe('能源概览: End-use coverage is incomplete.');
  expect(serverMessage('名称已存在')).toBe('Name already exists');
  expect(serverMessage('核实空间：能源概览')).toBe('Verify space: 能源概览');
  expect(serverMessage('确认“能源概览”的 3 块分表上级')).toBe('Confirm the parent for 3 submeters in “能源概览”');
  expect(serverMessage('能源概览：有效历史不足，至少需要 28 个有效日、80% 完整率和最近 7 天完整数据；长周期预测还需要足够的历史回测范围')).toContain('能源概览: Insufficient valid history.');
  expect(serverMessage('Unknown technical detail')).toBe('Unknown technical detail');
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
 it('loads a saved choice before translating shared labels',async()=>{
  vi.stubGlobal('navigator',{language:'zh-CN'});
  vi.stubGlobal('localStorage',{getItem:()=> 'en-US'});
  const {locale,languagePreference}=await import('./i18n');
  const {reportNames}=await import('./types');
  expect(languagePreference).toBe('en-US');expect(locale).toBe('en-US');
  expect(reportNames.dashboard).toBe('Energy overview');
 });
 it.each(['fr-FR','invalid','__proto__'])('ignores unsupported saved language %s',async stored=>{
  vi.stubGlobal('navigator',{language:'zh-CN'});
  vi.stubGlobal('localStorage',{getItem:()=>stored});
  const {locale,languagePreference}=await import('./i18n');
  expect(languagePreference).toBe('auto');expect(locale).toBe('zh-CN');
 });
 it('still detects the browser language if preference storage is blocked',async()=>{
  vi.stubGlobal('navigator',{language:'zh-CN'});
  vi.stubGlobal('localStorage',{getItem:()=>{throw new Error('blocked');}});
  const {locale}=await import('./i18n');expect(locale).toBe('zh-CN');
 });
 it('persists a manual choice and reloads the same project and view',async()=>{
  const storage={getItem:()=>null,setItem:vi.fn(),removeItem:vi.fn()};
  const location={href:'https://fin.example/seed/?project=demo#/profile?project=demo',search:'?project=demo',reload:vi.fn(),replace:vi.fn()};
  vi.stubGlobal('localStorage',storage);vi.stubGlobal('location',location);
  const {changeLanguage,localeStorageKey}=await import('./i18n');
  changeLanguage('en-US');expect(storage.setItem).toHaveBeenCalledWith(localeStorageKey,'en-US');
  expect(location.reload).toHaveBeenCalledOnce();expect(location.replace).not.toHaveBeenCalled();
 });
 it('clears a saved choice when returning to the browser language',async()=>{
  const storage={getItem:()=> 'en-US',setItem:vi.fn(),removeItem:vi.fn()};
  vi.stubGlobal('localStorage',storage);
  vi.stubGlobal('location',{href:'https://fin.example/seed/#/profile?project=demo',search:'',reload:vi.fn(),replace:vi.fn()});
  const {changeLanguage,localeStorageKey}=await import('./i18n');
  changeLanguage('auto');expect(storage.removeItem).toHaveBeenCalledWith(localeStorageKey);
 });
 it('uses a URL fallback when preference storage cannot be written',async()=>{
  const location={href:'https://fin.example/seed/?project=demo#/profile?project=demo',search:'?project=demo',reload:vi.fn(),replace:vi.fn()};
  vi.stubGlobal('localStorage',{getItem:()=>null,setItem:()=>{throw new Error('blocked');}});
  vi.stubGlobal('location',location);
  const {changeLanguage,readLanguagePreference}=await import('./i18n');
  changeLanguage('en-US');const next=new URL(location.replace.mock.calls[0][0]);
  expect(next.hash).toBe('#/profile?project=demo');expect(next.searchParams.get('project')).toBe('demo');
  expect(readLanguagePreference(undefined,next.search)).toBe('en-US');
 });
});
