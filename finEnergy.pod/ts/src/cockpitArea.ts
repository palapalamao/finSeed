import type {CockpitAreaFormula,CockpitAreaResolution} from './cockpitTypes';
import {locale,t} from './i18n';
export const cockpitAreaNumber=(value:number|null)=>value!=null&&Number.isFinite(value)?new Intl.NumberFormat(locale,{maximumFractionDigits:3}).format(value):'—';
export function cockpitAreaFormulaText(formula:CockpitAreaFormula):string{
 return t('{0} {1} ÷ {2} m² = {3} {4}',cockpitAreaNumber(formula.numerator.value),formula.numerator.unit,cockpitAreaNumber(formula.denominator.value),cockpitAreaNumber(formula.value),formula.unit);
}
export function cockpitAreaStatusText(resolution:CockpitAreaResolution):string{
 if(resolution.status==='missingArea')return t('统计面积缺失或无效，能耗数值仍保留。');
 if(resolution.status==='ambiguousArea')return t('服务面积边界不明确，保留能耗，不计算混合单位面积指标。');
 return resolution.basis==='nativeSpace'?t('按原生服务空间去重，面积只计一次。'):resolution.basis==='custom'?t('使用明确配置的自定义服务面积。'):t('请核对本次统计面积的来源与边界。');
}
