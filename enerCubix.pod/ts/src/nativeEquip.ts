import {t} from './i18n';
import type {FinPoint,EnerCubixRecord} from './types';
export const isNativeEquip=(row:Partial<EnerCubixRecord>)=>row.nativeEquip===true||row.nativeSourceKind==='equip';
export function mainEnergySources(records:EnerCubixRecord[]):Map<string,EnerCubixRecord>{
 return new Map(records.filter(row=>['meter','totalMeter'].includes(row.kind)&&typeof row.pointId==='string'&&!!row.pointId&&!row.expressionId&&(!row.canonicalId||row.canonicalId===row.id)).map(row=>[String(row.pointId),row]));
}
const units:Record<string,string>={Wh:'energy',kWh:'energy',MWh:'energy',J:'energy',kJ:'energy',MJ:'energy',GJ:'energy',m3:'volume','m³':'volume',L:'volume',l:'volume',ft3:'volume',gal:'volume',W:'power',kW:'power',MW:'power',kg:'mass',t:'mass'};
export const compatibleUnit=(a:string,b:string)=>a===b||!!units[a]&&units[a]===units[b];
export function primaryCandidates(points:FinPoint[],equipId:string|undefined,unit?:string){return points.filter(point=>point.equipId===equipId&&point.his&&(!unit||compatibleUnit(point.unit||'',unit)));}
export function enrollmentRecord(equip:EnerCubixRecord,point:FinPoint,categoryId:string|undefined,name?:string):EnerCubixRecord{
 if(point.equipId!==equip.id||!point.his)throw new Error(t("请选择本设备下已开启历史的主能耗点"));
 const alias=name?.trim();
 return {id:equip.id,mod:equip.mod,kind:'meter',name:alias||equip.name,useAlias:!!alias,pointId:point.id,categoryId,unit:point.unit,historyMode:'auto',includeInTotals:true,alarmEnabled:false,nativeEquip:true};
}
export const finEquipUrl=(project:string,id:string)=>`/finMobile/${encodeURIComponent(project)}#_builder?lhs=builder&targetRef=@${id}`;
