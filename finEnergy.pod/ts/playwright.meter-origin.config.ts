import {defineConfig} from '@playwright/test';
import config from './playwright.config';
export default defineConfig({...config,outputDir:'../../out/meter-origin-browser',reporter:[['list'],['html',{open:'never',outputFolder:'../../out/meter-origin-browser-report'}]],use:{...config.use,baseURL:'http://127.0.0.1:4191'},webServer:{command:'npx vite preview --host 127.0.0.1 --port 4191 --strictPort',url:'http://127.0.0.1:4191',reuseExistingServer:false,timeout:30000}});
