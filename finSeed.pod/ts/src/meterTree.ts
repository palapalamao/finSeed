import {nodeKinds,type SeedRecord} from './types';
export function branchIds(records:SeedRecord[],id:string):Set<string>{
 const ids=new Set([id]);const queue=[id];for(let i=0;i<queue.length;i++)for(const row of records)if(row.parentId===queue[i]&&row.id&&!ids.has(row.id)){ids.add(row.id);queue.push(row.id);}return ids;
}
export function objectPath(records:SeedRecord[],id?:string):SeedRecord[]{
 const path:SeedRecord[]=[];const seen=new Set<string>();let current=id;while(current&&!seen.has(current)){seen.add(current);const row=records.find(item=>item.id===current);if(!row)break;path.unshift(row);current=typeof row.parentId==='string'?row.parentId:undefined;}return path;
}
export function scopedObjects(records:SeedRecord[],id:string|undefined,scope:'children'|'branch'|'all'){
 const nodes=records.filter(row=>nodeKinds.includes(row.kind));if(scope==='all')return nodes;
 if(scope==='branch'&&id){const ids=branchIds(nodes,id);return nodes.filter(row=>row.id!==id&&ids.has(row.id!));}
 return nodes.filter(row=>(row.parentId||undefined)===id);
}
export function targetGroups(records:SeedRecord[],ids:string[]){
 const forbidden=new Set(ids.flatMap(id=>[...branchIds(records,id)]));return records.filter(row=>row.kind==='group'&&!forbidden.has(row.id!));
}
