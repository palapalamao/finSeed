import {afterEach,expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {initializeLocale,serverMessage} from './i18n';
import {createLicenseRequest,type LicenseStatus} from './license';
import {LicenseDetails} from './LicenseSettings';

const trial:LicenseStatus={status:'trial',used:11,limit:10,overLimit:true,canImport:false};
afterEach(()=>initializeLocale('en-US'));

it('exports only the native FIN machine identity and application request metadata',()=>{
 expect(createLicenseRequest('HID-example',new Date('2026-11-13T00:00:00Z'))).toEqual({
  version:1,product:'finEnergy',hostId:'HID-example',requestedAt:'2026-11-13T00:00:00.000Z'
 });
});

it.each([['zh-CN','项目已超出免费额度','FIN 机器码'],['en-US','This project exceeds its free meter allowance','FIN machine code']])(
 'keeps the recovery instructions accessible in %s without exposing a machine code to read-only users',
 (language,warning,machineLabel)=>{
  initializeLocale(language);
  const html=renderToStaticMarkup(<LicenseDetails status={trial}/>);
  expect(html).toContain(warning);
  expect(html).not.toContain(machineLabel);
  expect(html).not.toContain('HID-example');
 });

it('distinguishes an active training license from a host license and shows the current machine code',()=>{
 initializeLocale('en-US');
 const html=renderToStaticMarkup(<LicenseDetails status={{
  status:'active',used:42,limit:null,overLimit:false,canImport:true,hostId:'HID-example',
  licenseType:'training',expiresAt:'2106-01-13T15:59:00Z'
 }}/>);
 expect(html).toContain('Training license');
 expect(html).toContain('HID-example');
 expect(html).toContain('Unlimited');
 expect(html).toContain('2106');
});

it.each([['zh-CN','授权文件中的有效期有误。'],['en-US','The license contains an invalid validity period.']])(
 'reports a signed license with invalid dates in %s', (language,prefix)=>{
  initializeLocale(language);
  expect(serverMessage('licenseInvalidPeriod')).toContain(prefix);
 });
