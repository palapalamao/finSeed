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
 return sites.map(site=>({site,floors:nodes.filter(node=>node.nodeKind==='floor'&&node.parentId===site.id)}));
}
/** Ancestors may remain visible as context, without becoming a professional target. */
export function cockpitSpaceFocusIds(snapshot:CockpitSnapshot,catalog:Catalog,nodes=cockpitSpaceObjects(snapshot,catalog)){
 const scope=snapshot.context.reportScope,allowed=new Set([...scope.nodeIds,...focusRecords(catalog,scope).flatMap(row=>[row.id,row.nativeSourceId]).filter((id):id is string=>typeof id==='string')]);
 if(scope.dimension==='space')for(const candidate of nodes){let node:CockpitSpaceNode|undefined=candidate;const seen=new Set<string>();while(node&&!seen.has(node.id)){if(allowed.has(node.id)||allowed.has(node.nativeId)){allowed.add(candidate.id);break;}seen.add(node.id);node=nodes.find(parent=>parent.id===node!.parentId);}}
 return allowed;
}
/** Choose only objects in this observation. Catalogue ancestors never supply site totals. */
export function cockpitDefaultSpaceFocus(snapshot:CockpitSnapshot,catalog:Catalog,current?:string):string|undefined{
 if(!snapshot.capabilities.canRead)return;
 const all=cockpitSpaceObjects(snapshot,catalog),allowed=cockpitSpaceFocusIds(snapshot,catalog,all),nodes=all.filter(node=>allowed.has(node.id)||allowed.has(node.nativeId));
 if(current&&nodes.some(node=>node.id===current))return current;
 if(!snapshot.modules.space?.data)return;
 const readable=nodes.filter(node=>node.quality!=='notLoaded'&&!node.reasonCodes.some(code=>code==='notLoaded'||code==='FOCUS_NOT_LOADED'));
 const sites=readable.filter(node=>node.nodeKind==='site').sort((a,b)=>a.id.localeCompare(b.id,'en'));
 const scope=snapshot.context.reportScope.nodeIds;
 const scopeSite=scope.flatMap(id=>{const chain:string[]=[];let node=nodes.find(node=>node.id===id);while(node&&!chain.includes(node.id)){chain.push(node.id);node=nodes.find(parent=>parent.id===node?.parentId);}return chain;});
 return sites.find(node=>scopeSite.includes(node.id))?.id||sites[0]?.id||readable.find(node=>scope.includes(node.id))?.id||readable.sort((a,b)=>a.id.localeCompare(b.id,'en'))[0]?.id;
}
export function cockpitSpaceUsage(node:CockpitSpaceNode){
 const complete=node.valueBasis==='complete'&&node.completeValue!=null;
 const value=node.valueType==='na'?null:complete?node.completeValue:node.value??node.knownValue;
 return {complete,value,valueType:node.valueType==='na'?'na' as const:value==null?'null' as const:'number' as const};
}
export function cockpitSpaceIssues(snapshot:CockpitSnapshot,node:CockpitSpaceNode){
 const ids=new Set([node.id,node.nativeId,...node.meterIds]);return (snapshot.modules.issues?.data?.items||[]).filter(item=>ids.has(item.objectId)||item.sourceIds.some(id=>node.sourceIds.includes(id)));
}

/** Only explicit same-packet memberships are shown. Unknown or inaccessible IDs never become display labels. */
export function cockpitSpaceAssociations(snapshot:CockpitSnapshot,catalog:Catalog,focused:CockpitSpaceNode){
 const nodes=snapshot.modules.space?.data?.nodes||[],lookup=(id:string)=>catalog.records.find(row=>row.id===id||row.nativeSourceId===id);
 const members=focused.meterIds.map(id=>nodes.find(node=>(node.id===id||node.nativeId===id)&&node.nodeKind==='equip'));
 const items=members.filter((node):node is CockpitSpaceNode=>!!node).map(node=>({node,name:node.name||lookup(node.id)?.name,points:node.sourceIds.map(id=>({id,name:lookup(id)?.name})),issues:(snapshot.modules.issues?.data?.items||[]).filter(item=>item.sourceIds.some(id=>node.sourceIds.includes(id)))}));
 return {items,unresolved:members.some(node=>!node)||items.some(item=>!item.name||item.points.some(point=>!point.name))};
}
