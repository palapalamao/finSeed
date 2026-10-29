import {defineConfig} from '@playwright/test';
import base from './playwright.config';
export default defineConfig({...base,testMatch:'costReports.spec.ts',reporter:[['list']],use:{...base.use,baseURL:'http://127.0.0.1:4187'},webServer:{command:'node node_modules/vite/bin/vite.js preview --host 127.0.0.1 --port 4187 --strictPort',url:'http://127.0.0.1:4187',reuseExistingServer:false,timeout:30000}});
