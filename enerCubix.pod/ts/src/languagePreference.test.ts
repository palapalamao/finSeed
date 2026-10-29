import {afterEach,expect,it,vi} from 'vitest';

afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});

function browser(){
 const saved=new Map<string,string>();
 const storage={getItem:(key:string)=>saved.get(key)??null,setItem:(key:string,value:string)=>saved.set(key,value),removeItem:(key:string)=>saved.delete(key)};
 const location={href:'https://fin.example/index.html#/profile?project=cubeTest&template=saved',reload:vi.fn()};
 vi.stubGlobal('localStorage',storage);vi.stubGlobal('location',location);
 return {saved,storage,location};
}

it('retains a manual choice for the current FIN user while preserving the project and view',async()=>{
 const {saved,location}=browser();
 const i18n=await import('./i18n');
 i18n.initializeLocale('en','alice');
 i18n.changeLanguage('zh-CN');
 expect([...saved.values()]).toEqual(['zh-CN']);
 expect(location.reload).toHaveBeenCalledOnce();
 expect(location.href).toContain('#/profile?project=cubeTest&template=saved');
 i18n.initializeLocale('en','alice');
 expect(i18n.locale).toBe('zh-CN');expect(i18n.languagePreference).toBe('zh-CN');
});

it('keeps different FIN users preferences separate and restores the FIN default',async()=>{
 const {saved}=browser();const i18n=await import('./i18n');
 i18n.initializeLocale('en','alice');i18n.changeLanguage('zh-CN');
 i18n.initializeLocale('en','bob');expect(i18n.locale).toBe('en-US');
 expect(i18n.languagePreference).toBe('auto');
 i18n.initializeLocale('en','alice');expect(i18n.locale).toBe('zh-CN');
 i18n.changeLanguage('auto');expect(saved.size).toBe(0);
 i18n.initializeLocale('en','alice');expect(i18n.locale).toBe('en-US');
 expect(i18n.languagePreference).toBe('auto');
});

it('does not read the old unscoped preference or browser language',async()=>{
 const {saved}=browser();saved.set('enerCubix.locale.v1','zh-CN');
 vi.stubGlobal('navigator',{language:'zh-CN'});
 const i18n=await import('./i18n');i18n.initializeLocale('en','alice');
 expect(i18n.locale).toBe('en-US');expect(i18n.languagePreference).toBe('auto');
});

it('does not reload or pretend a choice was saved if browser storage is blocked',async()=>{
 const {storage,location}=browser();storage.setItem=()=>{throw new Error('blocked');};
 const i18n=await import('./i18n');i18n.initializeLocale('en','alice');
 expect(()=>i18n.changeLanguage('zh-CN')).toThrow('Unable to save');
 expect(location.reload).not.toHaveBeenCalled();expect(i18n.locale).toBe('en-US');
});
