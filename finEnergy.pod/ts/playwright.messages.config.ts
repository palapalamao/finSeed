import {defineConfig} from '@playwright/test';
import base from './playwright.config';

export default defineConfig(base,{
 testMatch:['**/message-center.spec.ts','**/alarm-episodes.spec.ts','**/rebrand.spec.ts'],
 reporter:'list',
 use:{...base.use,baseURL:'http://127.0.0.1:4196'},
 webServer:{command:'npx vite preview --host 127.0.0.1 --port 4196 --strictPort',url:'http://127.0.0.1:4196',reuseExistingServer:false,timeout:30000}
});
