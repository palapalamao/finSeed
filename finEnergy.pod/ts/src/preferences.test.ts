import {expect,it} from 'vitest';
import {readPreference} from './preferences';
it('moves a scoped setting once and respects the current product preference',()=>{
 const map=new Map([['old.user.project','15']]);const store={getItem:(key:string)=>map.get(key)??null,setItem:(key:string,value:string)=>map.set(key,value),removeItem:(key:string)=>map.delete(key)};
 expect(readPreference(store,'new.user.project','old.user.project')).toBe('15');expect(map.has('old.user.project')).toBe(false);
 map.set('old.user.project','5');expect(readPreference(store,'new.user.project','old.user.project')).toBe('15');
 expect(readPreference(store,'new.other.project','old.other.project')).toBe(null);
});
