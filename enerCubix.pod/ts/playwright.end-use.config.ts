import {defineConfig} from '@playwright/test';
import base from './playwright.config';
export default defineConfig({...base,testMatch:['**/end-use.spec.ts','**/energy-flow-views.spec.ts','**/energy-flow-scope.spec.ts','**/versioned-entry.spec.ts','**/leak-available-difference.spec.ts'],reporter:'list',use:{...base.use,baseURL:'http://127.0.0.1:4198'},webServer:{command:`"${process.execPath}" node_modules/vite/bin/vite.js preview --host 127.0.0.1 --port 4198 --strictPort`,url:'http://127.0.0.1:4198',reuseExistingServer:false,timeout:30000}});
