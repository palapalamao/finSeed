import {vi} from 'vitest';
// Existing regression fixtures explicitly exercise the Chinese interface.
vi.stubGlobal('navigator',{language:'zh-CN',languages:['zh-CN']});
