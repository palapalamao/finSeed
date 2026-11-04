import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {gzipSync} from 'node:zlib';

// Compare production dependency closures, not just the renamed entry chunk.
const root=resolve(process.argv[2]||'enerCubix.pod/res/web/enerCubix');
const manifest=JSON.parse(readFileSync(resolve(root,'.vite/manifest.json'),'utf8'));
const closure=(keys,seen=new Set())=>{for(const key of keys){if(seen.has(key)||!manifest[key])continue;seen.add(key);closure(manifest[key].imports||[],seen);}return seen;};
const files=keys=>[...new Set([...closure(keys)].map(key=>manifest[key].file))].filter(file=>file.endsWith('.js'));
const measure=keys=>{const list=files(keys);return {files:list,bytes:list.reduce((sum,file)=>sum+readFileSync(resolve(root,file)).length,0),gzipBytes:list.reduce((sum,file)=>sum+gzipSync(readFileSync(resolve(root,file))).length,0)};};
const keyFor=name=>Object.keys(manifest).find(key=>manifest[key].name===name);
const app=keyFor('App'),cockpit=keyFor('CockpitPage');
const report={generatedAt:new Date().toISOString(),basis:'Uncompressed production JavaScript and local gzip size; not measured HTTP transfer or FIN elapsed time',beforeCatalog:measure(['index.html',app]),homepage:measure(['index.html',app,cockpit]),pages:Object.fromEntries(['App','CockpitPage','Management','MessageCenter','ReportWorkspace'].map(name=>[name,manifest[keyFor(name)]||null]))};
if(process.argv[3]){const output=resolve(process.argv[3]);mkdirSync(dirname(output),{recursive:true});writeFileSync(output,JSON.stringify(report,null,2));}
console.log(JSON.stringify(report,null,2));
