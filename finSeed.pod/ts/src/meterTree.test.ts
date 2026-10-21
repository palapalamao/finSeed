import {describe,it,expect} from 'vitest';
import {branchIds,objectPath,scopedObjects,targetGroups} from './meterTree';
import type {SeedRecord} from './types';
const records:SeedRecord[]=[{id:'a',kind:'group',name:'园区'},{id:'b',parentId:'a',kind:'group',name:'楼栋'},{id:'m',parentId:'b',kind:'meter',name:'电表'},{id:'other',kind:'group',name:'另一园区'},{id:'cat',kind:'category',name:'电'}];
describe('tree engineering scope',()=>{
 it('shows direct children separately from descendants and all objects',()=>{expect(scopedObjects(records,'a','children').map(r=>r.id)).toEqual(['b']);expect(scopedObjects(records,'a','branch').map(r=>r.id)).toEqual(['b','m']);expect(scopedObjects(records,undefined,'children').map(r=>r.id)).toEqual(['a','other']);expect(scopedObjects(records,'a','all')).toHaveLength(4);});
 it('uses references rather than names for paths and move targets',()=>{expect(objectPath(records,'m').map(r=>r.name)).toEqual(['园区','楼栋','电表']);expect(targetGroups(records,['b']).map(r=>r.id)).toEqual(['a','other']);});
 it('bounds corrupt cycles without freezing the page',()=>{const cycle=[{id:'a',parentId:'b',kind:'group',name:'a'},{id:'b',parentId:'a',kind:'group',name:'b'}]as SeedRecord[];expect(branchIds(cycle,'a').size).toBe(2);expect(objectPath(cycle,'a')).toHaveLength(2);});
});
