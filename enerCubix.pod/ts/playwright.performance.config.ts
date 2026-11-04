import {defineConfig} from '@playwright/test';
import base from './playwright.config';
export default defineConfig(base,{use:{baseURL:'http://127.0.0.1:4189'},webServer:{command:'npx vite preview --host 127.0.0.1 --port 4189 --strictPort',url:'http://127.0.0.1:4189',reuseExistingServer:false,timeout:30000}});
