import {t} from './i18n';
import type {EnerCubixRecord} from './types';

export type CleaningMode='drop'|'replace'|'rollover';
export type CleaningNumber=number|{type:'number';value:number;unit?:string};
export interface CleaningParameters {deltaMin?:CleaningNumber;deltaMax?:CleaningNumber;timeMax?:string;derivMin?:CleaningNumber;derivMax?:CleaningNumber;defVal?:{type:'number';value:number;unit?:string}|{type:'na'};defNull?:true;removeNA?:true;hisTotalizedRollover?:CleaningNumber}
export interface NumericRule {enabled:boolean;value?:number|null;unit:string}
export const cleaningBounds=['deltaMin','deltaMax','derivMin','derivMax'] as const;
export type CleaningBound=typeof cleaningBounds[number];
export interface CleaningDraft {name:string;mode:CleaningMode;deltaMin:NumericRule;deltaMax:NumericRule;derivMin:NumericRule;derivMax:NumericRule;timeMaxEnabled:boolean;timeMax:string;removeNA:boolean;defVal:NumericRule;defValNA:boolean;hisTotalizedRollover:NumericRule}
export interface CleaningPreview {pointId?:string;status?:string;unit?:string;from?:string;to?:string;raw:{ts:string;value:number|null;valueType?:'number'|'na'|'null'}[];cleaned:{ts:string;value:number|null;valueType?:'number'|'na'|'null';quality?:string}[];details:Record<string,unknown>[];summary:Record<string,unknown>;profileSnapshot:Record<string,unknown>}
const numericRule=(value:unknown):NumericRule=>typeof value==='number'?{enabled:true,value,unit:''}:value&&typeof value==='object'&&(value as {type?:string}).type==='number'?{enabled:true,value:(value as {value:number}).value,unit:String((value as {unit?:string}).unit||'')}:{enabled:false,value:null,unit:''};
export function cleaningDraft(profile?:Partial<EnerCubixRecord>|Record<string,unknown>):CleaningDraft{
 const p=(profile?.parameters||(!profile?{deltaMin:0,timeMax:'1h',defNull:true}:{})) as CleaningParameters;
 return {name:profile?.name as string||'',mode:(profile?.mode as CleaningMode)||'drop',deltaMin:numericRule(p.deltaMin),deltaMax:numericRule(p.deltaMax),derivMin:numericRule(p.derivMin),derivMax:numericRule(p.derivMax),timeMaxEnabled:!!p.timeMax,timeMax:p.timeMax||'',removeNA:p.removeNA===true,defVal:numericRule(p.defVal),defValNA:p.defVal?.type==='na',hisTotalizedRollover:numericRule(p.hisTotalizedRollover)};
}
function numericValue(rule:NumericRule,explicit=false):CleaningNumber|undefined{
 if(!rule.enabled||rule.value===null||rule.value===undefined)return undefined;
 if(!Number.isFinite(rule.value))throw new Error(t('请输入有效数值'));
 const unit=rule.unit.trim();return explicit||unit?{type:'number',value:rule.value,...(unit?{unit}:{})}:rule.value;
}
export function cleaningParameters(draft:CleaningDraft):CleaningParameters{
 const parameters:CleaningParameters={};
 for(const key of cleaningBounds){const value=numericValue(draft[key]);if(value!==undefined)parameters[key]=value;}
 for(const [min,max]of [['deltaMin','deltaMax'],['derivMin','derivMax']] as const){const a=draft[min],b=draft[max];if(a.enabled&&b.enabled&&a.value!=null&&b.value!=null&&a.unit.trim()===b.unit.trim()&&a.value>b.value)throw new Error(t('最小值不能大于最大值'));}
 if(draft.timeMaxEnabled&&draft.timeMax.trim()){
  if(!/^(?:\d+(?:\.\d+)?)(?:ms|sec|s|min|h|hr|day|d|wk|week)$/.test(draft.timeMax.trim())||Number.parseFloat(draft.timeMax)<=0)throw new Error(t('请输入正的时间间隔，例如 1h 或 30min'));
  parameters.timeMax=draft.timeMax.trim();
 }
 if(draft.removeNA)parameters.removeNA=true;
 if(draft.mode==='drop')parameters.defNull=true;
 else if(draft.mode==='replace'){
  if(draft.defValNA)parameters.defVal={type:'na'};
  else{const value=numericValue({...draft.defVal,enabled:true},true);if(value===undefined)throw new Error(t('请填写替代值或选择 NA'));parameters.defVal=value as CleaningParameters['defVal'];}
 }else{
  const period=numericValue({...draft.hisTotalizedRollover,enabled:true});
  if(period===undefined||(typeof period==='number'?period:period.value)<=0||(parameters.deltaMax===undefined&&parameters.derivMax===undefined))throw new Error(t('回绕模式需要计数周期和增量上限或变化率上限'));
  parameters.hisTotalizedRollover=period;
 }
 return parameters;
}
export function previewRangeError(from:string,to:string):string|undefined{
 const start=Date.parse(from),end=Date.parse(to);
 if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)return t('请选择有效的开始与结束时间，结束时间须晚于开始时间');
 if(end-start>31*86400000)return t('预览区间不能超过 31 天');
}
export const cleaningModeNames:Record<CleaningMode,string>={drop:t('过滤异常'),replace:t('替代异常'),rollover:t('累计表回绕')};
export function cleaningReason(reason:string){
 return ({ok:t('正常'),noPrevious:t('无前一读数'),removedNA:t('已移除原始 NA'),unalignedSources:t('来源区间未对齐'),externalNull:t('外部清洗结果为空'),deltaMin:t('低于最小增量'),deltaMax:t('超过最大增量'),derivMin:t('低于最小变化率'),derivMax:t('超过最大变化率'),timeMax:t('超过最大读数间隔'),inputNA:t('原始读数为 NA'),previousNA:t('前一读数为 NA'),inputNull:t('原始读数为空'),previousNull:t('前一读数为空'),invalidValue:t('无效读数'),nonPositiveInterval:t('读数时间未递增'),rollover:t('回绕已修正'),rolloverOutOfRange:t('读数超出计数周期')} as Record<string,string>)[reason]||t('数据异常（{0}）',reason);
}
export function cleaningScopeText(scope:unknown){return scope==='sourceIntervals'?t('源点区间处理次数；输出点数和覆盖率按当前对象计算'):scope==='objectIntervals'?t('当前对象的区间处理次数'):String(scope);}
