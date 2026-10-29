import {initializeLocale} from '../src/i18n';
import {beforeEach} from 'vitest';
// Existing regression fixtures explicitly exercise a Chinese FIN user.
initializeLocale('zh-CN');
beforeEach(async()=>{(await import('../src/i18n')).initializeLocale('zh-CN');});
