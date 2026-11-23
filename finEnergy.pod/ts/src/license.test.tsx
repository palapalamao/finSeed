import {afterEach,expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {initializeLocale,serverMessage} from './i18n';
import type {LicenseStatus} from './license';
import {LicenseDetails} from './LicenseSettings';
const active:LicenseStatus={source:'fin',status:'active',feature:'finenergy',canManageFinLicense:true,hostId:'HID-example'};
afterEach(()=>initializeLocale('en-US'));
it.each([['zh-CN','FIN 原生授权','功能已授权'],['en-US','Native FIN license','Feature licensed']])('shows native ownership and verified status in %s',(language,source,status)=>{
 initializeLocale(language);const html=renderToStaticMarkup(<LicenseDetails status={active}/>);
 expect(html).toContain(source);expect(html).toContain(status);expect(html).toContain('finenergy');expect(html).toContain('HID-example');
 expect(html).not.toMatch(/type="file"|10 \/|Training license|Free allowance/);
});
it.each(['missingFeature','invalid','inactive'] as const)('keeps recovery navigation available for %s without exposing an unavailable Host ID',status=>{
 initializeLocale('en-US');const html=renderToStaticMarkup(<LicenseDetails status={{...active,status,canManageFinLicense:false,hostId:undefined,reason:'nativeLicenseRequired'}}/>);
 expect(html).toContain('FIN energy feature license required');expect(html).toContain('Host → Licenses');
 expect(html).toContain('Ask a FIN license administrator');expect(html).not.toContain('HID-example');
 expect(html).not.toContain('nativeLicenseRequired');
});
it.each([['zh-CN','能源功能授权'],['en-US','energy feature license']])('translates the native backend denial in %s',(language,text)=>{
 initializeLocale(language);expect(serverMessage('nativeLicenseRequired')).toContain(text);
});
