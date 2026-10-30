import {t} from './i18n';
import type {EnerCubixRecord,ReportSnapshot} from './types';
export const isAreaSpace=(row:Partial<EnerCubixRecord>)=>row.nativeReadonly===true&&['site','floor'].includes(String(row.nativeSourceKind));
export const areaSpaces=(records:EnerCubixRecord[])=>records.filter(isAreaSpace);
export function spaceAreaPayload(row:EnerCubixRecord,area:number|null):EnerCubixRecord{
 // The area-only wire payload deliberately omits the full record's name and refs.
 return {id:row.id,mod:row.mod,kind:'space',areaOnly:true,area} as unknown as EnerCubixRecord;
}
interface AreaBasis {nodeId:string;categoryId?:string;name?:string;basis?:string;baseValue:number|null;baseUnit:string;value:number|null;unit:string;area:{value:number|null;quality:string;unit:string;sources:{id:string;name:string;area:number|null;source:'space'|'custom'}[]}}
const number=(value:number|null|undefined)=>typeof value==='number'&&Number.isFinite(value)?value.toLocaleString('en-US',{maximumFractionDigits:6}):'—';
export function areaBasisRows(snapshot:ReportSnapshot):string[][]{
 const rows=(snapshot.result.extra?.areaBasis||[]) as AreaBasis[];
 return rows.map(row=>{
  const name=row.nodeId==='__selection__'?t('所选范围合计'):row.name||snapshot.display?.objects[row.nodeId]||t('对象名称不可用');
  const area=row.area,base=`${number(row.baseValue)} ${row.baseUnit}`,valid=area.quality==='ok'&&typeof area.value==='number'&&area.value>0;
  const calculation=valid?`${base} ÷ ${number(area.value)} m² = ${number(row.value)} ${row.unit}`:t('已有用量 {0}；{1}；单位面积指标不可用',base,t(area.quality==='ambiguousArea'?'面积边界不明确，请引用服务空间':'未配置有效统计面积'));
  const sources=area.sources.map(source=>t('{0}：{1} m²（{2}）',source.name,number(source.area),t(source.source==='space'?'服务空间':'自定义服务面积'))).join('；');
  const category=row.categoryId?snapshot.display?.objects[row.categoryId]:undefined;
  const label=category?t('{0} · {1}',name,category):name;
  return [row.basis==='difference'?t('{0}（总分表差额）',label):label,calculation,sources||'—'];
 });
}
