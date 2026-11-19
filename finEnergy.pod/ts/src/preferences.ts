/** Migrate only explicitly scoped keys; never adopt a legacy global locale. */
export function readPreference(storage:Pick<Storage,'getItem'|'setItem'|'removeItem'>,key:string,legacyKey:string):string|null{
 const current=storage.getItem(key);
 if(current!==null){storage.removeItem(legacyKey);return current;}
 const legacy=storage.getItem(legacyKey);
 if(legacy===null)return null;
 storage.setItem(key,legacy);
 storage.removeItem(legacyKey);
 return legacy;
}
