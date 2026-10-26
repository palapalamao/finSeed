import {defineConfig} from '@playwright/test';
import base from './playwright.config';
export default defineConfig(base,{
 testMatch:'**/comparison-scopes.spec.ts',reporter:'list',
 use:{...base.use,baseURL:'http://127.0.0.1:4195'},
 webServer:{command:'npx vite --host 127.0.0.1 --port 4195 --strictPort',url:'http://127.0.0.1:4195',reuseExistingServer:false,timeout:30000}
});
