import {t} from './i18n';
import type {FinPoint,SeedRecord} from './types';
export const isNativeEquip=(row:Partial<SeedRecord>)=>row.nativeEquip===true||row.nativeSourceKind==='equip';
const units:Record<string,string>={Wh:'energy',kWh:'energy',MWh:'energy',J:'energy',kJ:'energy',MJ:'energy',GJ:'energy',m3:'volume','m³':'volume',L:'volume',l:'volume',ft3:'volume',gal:'volume',W:'power',kW:'power',MW:'power',kg:'mass',t:'mass'};
export const compatibleUnit=(a:string,b:string)=>a===b||!!units[a]&&units[a]===units[b];
export function primaryCandidates(points:FinPoint[],equipId:string|undefined,unit?:string){return points.filter(point=>point.equipId===equipId&&point.his&&(!unit||compatibleUnit(point.unit||'',unit)));}
export function enrollmentRecord(equip:SeedRecord,point:FinPoint,categoryId:string|undefined,name=equip.name):SeedRecord{
 if(point.equipId!==equip.id||!point.his)throw new Error(t("请选择本设备下已开启历史的主能耗点"));
 return {id:equip.id,mod:equip.mod,kind:'meter',name,pointId:point.id,categoryId,unit:point.unit,historyMode:'auto',includeInTotals:true,alarmEnabled:false,nativeEquip:true};
}
export const finEquipUrl=(project:string,id:string)=>`/finMobile/${encodeURIComponent(project)}#_builder?lhs=builder&targetRef=@${id}`;
