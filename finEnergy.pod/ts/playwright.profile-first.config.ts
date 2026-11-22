import {defineConfig} from '@playwright/test';
import base from './playwright.config';
export default defineConfig({...base,testMatch:'profile-first.spec.ts',outputDir:'../../.local/profile-first-validation/browser-results',use:{...base.use,baseURL:'http://127.0.0.1:4183'},webServer:{command:'npx vite preview --host 127.0.0.1 --port 4183 --strictPort',url:'http://127.0.0.1:4183',reuseExistingServer:false,timeout:30000}});
