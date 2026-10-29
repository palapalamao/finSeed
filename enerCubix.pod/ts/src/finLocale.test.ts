import {afterEach,expect,it,vi} from 'vitest';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});

it.each([
 ['zh','en-US','zh-CN','能源魔方 · 楼宇能源分析','zh-cn'],
 ['en','zh-CN','en-US','EnergyCubix · Building Energy Analytics','en'],
 ['fr','zh-CN','en-US','EnergyCubix · Building Energy Analytics','en']
])('uses FIN language %s despite conflicting browser, URL and saved preferences',async(finLanguage,browser,expected,title,dateLocale)=>{
 vi.stubGlobal('navigator',{language:browser,languages:[browser]});
 vi.stubGlobal('localStorage',{getItem:()=>browser});
 vi.stubGlobal('location',{search:'?enerCubixLang='+browser});
 vi.stubGlobal('document',{documentElement:{lang:''},title:''});
 const {initializeLocale}=await import('./i18n');
 initializeLocale(finLanguage);
 const i18n=await import('./i18n');
 const {productName}=await import('./brand');
 const {reportNames}=await import('./types');
 const {default:dayjs}=await import('dayjs');
 expect(i18n.locale).toBe(expected);
 expect(document.documentElement.lang).toBe(expected);
 expect(document.title).toBe(title);
 expect(productName).toBe(expected==='zh-CN'?'能源魔方':'EnergyCubix');
 expect(reportNames.dashboard).toBe(expected==='zh-CN'?'能源概览':'Energy overview');
 expect(dayjs.locale()).toBe(dateLocale);
});
