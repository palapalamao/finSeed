import {dimensionRoots} from './dimensionTree';
import type {FinPoint,EnerCubixRecord} from './types';

export interface PointNode {key:string;title:string;point?:FinPoint;children:PointNode[];checkable:boolean;isLeaf:boolean}

export function finPointRoots(records:EnerCubixRecord[],points:FinPoint[],nativeSpace:boolean):PointNode[]{
 const eligible=new Map(points.filter(point=>point.his===true).map(point=>[point.id,point]));
 const sources=nativeSpace?records.filter(row=>row.kind==='space'&&row.nativeReadonly===true||row.kind==='nativePoint'):[];
 if(!nativeSpace){
  const containers=new Set<string>();
  for(const point of eligible.values()){
   let parentId:string|undefined;
   for(const [kind,id,name] of [['site',point.siteId,point.siteName],['floor',point.floorId,point.floorName],['equip',point.equipId,point.equipNavName||point.equipName]]){
    if(!id)continue;const key=`__fin:${kind}:${id}`;
    if(!containers.has(key)){containers.add(key);sources.push({id:key,kind:'space',name:name||id,parentId,nativeReadonly:true});}parentId=key;
   }
   sources.push({id:point.id,kind:'nativePoint',name:point.navName||point.name,parentId,nativeSourceId:point.id,his:true});
  }
 }
 const convert=(nodes:ReturnType<typeof dimensionRoots>):PointNode[]=>nodes.flatMap<PointNode>(node=>{
  const point=node.record?.kind==='nativePoint'?eligible.get(String(node.record.nativeSourceId||node.key)):undefined;
  if(node.record?.kind==='nativePoint')return point?[{key:point.id,title:node.title,point,children:[],checkable:true,isLeaf:true}]:[];
  const children=convert(node.children);return children.length?[{key:node.key,title:node.title,children,checkable:false,isLeaf:false}]:[];
 });
 return convert(dimensionRoots(sources,'space',true));
}

export function filterPointRoots(nodes:PointNode[],query:string):PointNode[]{
 const q=query.trim().toLocaleLowerCase();if(!q)return nodes;
 const filter=(rows:PointNode[],ancestorMatches=false):PointNode[]=>rows.flatMap(node=>{
  const matches=ancestorMatches||[node.title,node.key,node.point?.name].some(value=>value?.toLocaleLowerCase().includes(q));
  const children=filter(node.children,matches);return (node.point?matches:children.length)?[{...node,children}]:[];
 });
 return filter(nodes);
}

export function pointBranchKeys(nodes:PointNode[]):string[]{return nodes.flatMap(node=>node.point?[]:[node.key,...pointBranchKeys(node.children)]);}
