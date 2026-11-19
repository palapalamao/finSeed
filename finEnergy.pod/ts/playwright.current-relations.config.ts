import {defineConfig} from '@playwright/test';
import base from './playwright.config';

export default defineConfig(base,{
 testMatch:'**/leak-current-relations.spec.ts',
 reporter:'list',
 use:{...base.use,baseURL:'http://127.0.0.1:4194'},
 webServer:{command:'npx vite preview --host 127.0.0.1 --port 4194 --strictPort',url:'http://127.0.0.1:4194',reuseExistingServer:false,timeout:30000}
});
