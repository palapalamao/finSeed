import type {Dimension,FinPoint,Kind,EnerCubixRecord} from './types';
const unitKey=(value:unknown)=>String(value||'').trim().replace(/\s/g,'').replace(/³|\^3/g,'3');
const energyNames:Record<string,RegExp>={water:/^(水|自来水|生活水|冷水|热水|water)$/i,elec:/^(电|电力|电能|electric|electricity)$/i,gas:/^(气|燃气|天然气|gas|naturalgas)$/i,steam:/^(蒸汽|steam)$/i,heat:/^(热|热量|供热|heat|heating)$/i,cooling:/^(冷|冷量|供冷|cooling)$/i,oil:/^(油|燃油|燃料油|fuelOil|oil)$/i};
const nativeEnergy:Record<string,string>={hotwater:'water',chilledwater:'water',fueloil:'oil'};
export function inferPointCategory(records:EnerCubixRecord[],points:FinPoint[]):string|undefined{
 if(!points.length)return;const categories=records.filter(row=>row.kind==='category');const matches=points.map(point=>{if(!point.unit)return;let candidates=categories.filter(row=>unitKey(row.unit)===unitKey(point.unit));const tags=[...new Set((point.energyTags||[]).map(tag=>(nativeEnergy[tag.toLowerCase()]||tag.toLowerCase())).filter(tag=>tag in energyNames))];if(tags.length>1)return;if(tags.length)candidates=candidates.filter(row=>energyNames[tags[0]].test(row.name)||String(row.energyType||'').toLowerCase()===tags[0]);return candidates.length===1?candidates[0].id:undefined;});
 return matches.every(id=>id&&id===matches[0])?matches[0]:undefined;
}
export function nativePointInfo(row:EnerCubixRecord):FinPoint{return {id:String(row.nativeSourceId||row.id),name:String(row.nativeDis||row.name),navName:row.name,unit:typeof row.unit==='string'?row.unit:undefined,kind:typeof row.pointKind==='string'?row.pointKind:undefined,his:!!row.his,energyTags:Array.isArray(row.energyTags)?row.energyTags as string[]:undefined};}
export function suggestPointName(point:FinPoint,kind?:Kind):string{
 let name=(point.equipNavName||point.equipName||point.navName||point.name).trim();for(const prefix of [point.siteName,point.floorName]){const explicit=prefix?.trim();if(explicit&&name.startsWith(explicit)){const shorter=name.slice(explicit.length).replace(/^[\s/\\:：._-]+/,'');if(shorter)name=shorter;}}const measurement=point.navName?.trim();if(kind==='sensor'&&measurement&&!name.includes(measurement))name+=' '+measurement;return name||point.name;
}
export function newMeterDefaults(parent:EnerCubixRecord|undefined,dimension:Dimension,kind:Kind):Record<string,unknown>{
 if(!parent)return {};if(parent.kind==='space')return {spaceId:parent.id};if(parent.kind==='organization')return {organizationId:parent.id};if(parent.kind==='group')return {parentId:parent.id};if(dimension==='metering'&&['meter','totalMeter'].includes(parent.kind))return {meterParentId:parent.id,...(typeof parent.spaceId==='string'?{spaceId:parent.spaceId}:{}),...(typeof parent.organizationId==='string'?{organizationId:parent.organizationId}:{}),...(kind!=='sensor'&&parent.categoryId?{categoryId:parent.categoryId}:{})};return {};
}
