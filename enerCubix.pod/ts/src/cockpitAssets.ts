import type {CockpitSpaceNode} from './cockpitTypes';
import type {Catalog} from './types';
export interface CockpitHotspot {spaceId:string;x:number;y:number}
export interface CockpitAsset {unavailable?:false;id:string;mod:string;name:string;scopeId:string;hash:string;mime:'image/png'|'image/jpeg';width:number;height:number;size:number;updatedAt:string;updatedBy:string;hotspots:CockpitHotspot[]}
export interface UnavailableCockpitAsset {id:string;mod:string;unavailable:true;canManage:true}
export type CockpitAssetEntry=CockpitAsset|UnavailableCockpitAsset;
export const readableAsset=(item:CockpitAssetEntry):item is CockpitAsset=>!item.unavailable;
export interface CockpitAssetCatalog {projectId:string;items:CockpitAssetEntry[];manifestMod:string|null;selectedId:string|null;limits:{maxBytes:number;maxDimension:number;maxPixels:number;maxHotspots:number;maxAssets:number}}
export interface CockpitAssetEvidence {asset:CockpitAsset;displayed:boolean;observedAt:string;imageCaptured:false}
export function assetSpaces(catalog:Catalog){return catalog.records.filter(row=>row.kind==='space'&&!row.nativeHidden&&['site','floor'].includes(String(row.nativeSourceKind))).map(row=>({id:String(row.nativeSourceId||row.id),name:row.name}));}
export function hotspotNode(nodes:CockpitSpaceNode[],spaceId:string){return nodes.find(node=>(node.id===spaceId||node.nativeId===spaceId)&&['site','floor'].includes(node.nodeKind));}
