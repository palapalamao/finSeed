import type {Catalog,EnerCubixRecord} from './types';
import type {CockpitSnapshot,CockpitSpaceNode} from './cockpitTypes';
import {dimensionParent} from './dimensionTree';
import {focusRecords} from './cockpitNavigation';

/** Join display metadata only. Never aggregate children or synthesize own-point energy. */
export function cockpitSpaceObjects(snapshot:CockpitSnapshot,catalog:Catalog):CockpitSpaceNode[]{
 const loaded=snapshot.modules.space?.data?.nodes,rows=focusRecords(catalog,snapshot.context.reportScope);
 const record=(node:{id:string;nativeId?:string})=>catalog.records.find(row=>row.id===node.id||row.id===node.nativeId||row.nativeSourceId===node.nativeId);
 const kind=(row:EnerCubixRecord|undefined):CockpitSpaceNode['nodeKind']=>{const value=String(row?.nativeSourceKind||row?.nativeLevel||'');return value==='site'||value==='floor'||value==='point'?value:row?.kind==='nativePoint'?'point':'equip';};
 if(loaded)return loaded.map(node=>{const row=record(node);return {...node,name:node.name||row?.name||node.id,parentId:node.parentId!==undefined?node.parentId:row?dimensionParent(row,'space',catalog.spaceSource==='fin')||null:null};});
 return rows.map(row=>({id:row.id!,nativeId:String(row.nativeSourceId||row.id),name:row.name,parentId:dimensionParent(row,'space',catalog.spaceSource==='fin')||null,nodeKind:kind(row),basis:row.kind==='space'?'scopeAggregate':'ownPrimary',meterIds:[],sourceIds:[],value:null,knownValue:null,completeValue:null,valueType:'null',valueBasis:'unavailable',unit:'',quality:'notLoaded',reasonCodes:['notLoaded']}));
}
export function cockpitSpaceSites(nodes:CockpitSpaceNode[]){
 const sites=nodes.filter(node=>node.nodeKind==='site');
 return sites.map(site=>({site,floors:nodes.filter(node=>node.nodeKind==='floor'&&node.parentId===site.id)})).filter(item=>item.floors.length>0);
}
export function cockpitSpaceIssues(snapshot:CockpitSnapshot,node:CockpitSpaceNode){
 const ids=new Set([node.id,node.nativeId,...node.meterIds]);return (snapshot.modules.issues?.data?.items||[]).filter(item=>ids.has(item.objectId)||item.sourceIds.some(id=>node.sourceIds.includes(id)));
}
