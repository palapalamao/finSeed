import {afterEach, expect, it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {initializeLocale, serverMessage} from './i18n';
import {createLicenseRequest, type LicenseStatus} from './localLicense';
import {LicenseDetails} from './LocalLicenseSettings';

const trial:LicenseStatus={source:'product',edition:'china',status:'trial',used:11,limit:10,overLimit:true,canImport:true};
afterEach(()=>initializeLocale('en-US'));

it.each([['zh-CN','项目已超出免费额度'],['en-US','This project exceeds its free meter allowance']])('shows quota recovery in %s',(locale,expected)=>{
 initializeLocale(locale);
 expect(renderToStaticMarkup(<LicenseDetails status={trial}/>)).toContain(expected);
 expect(serverMessage('licenseProjectOverLimit')).not.toContain('licenseProjectOverLimit');
});

it('keeps the authorization request compatible with the existing signer',()=>{
 expect(createLicenseRequest('HID-test',new Date('2026-11-21T00:00:00Z'))).toEqual({
  version:1, product:'enerCubix', hostId:'HID-test', requestedAt:'2026-11-21T00:00:00.000Z'
 });
});
