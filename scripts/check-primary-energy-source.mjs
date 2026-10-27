import {readdirSync,readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join,relative} from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const violations=[];
const rules=[
 [/\.his\.(?:write|remove|delete|clear)\s*\(|\b(?:hisWrite|hisRemove|hisDelete|hisClear)\s*\(/,'runtime history mutation'],
 [/\bEnerCubixMeterGeneration\.(?:update|ensure|publish|recalculate)\s*\(/,'retired archive generation'],
 [/\bEnerCubixMeterHistory\.(?:load|loadDb|legacyConfig)\s*\(/,'retired archive source']
];
let checked=0;
function check(directory){
 for(const entry of readdirSync(directory,{withFileTypes:true})){
  const path=join(directory,entry.name);
  if(entry.isDirectory()){check(path);continue;}
  if(!entry.name.endsWith('.fan'))continue;
  checked++;
  const source=readFileSync(path,'utf8');
  for(const [pattern,reason] of rules)if(pattern.test(source))violations.push(`${relative(root,path)}: ${reason}`);
 }
}
check(join(root,'enerCubix.pod','fan'));
if(violations.length)throw new Error(violations.join('\n'));
console.log(`Primary energy source guard passed: ${checked} runtime source files.`);
