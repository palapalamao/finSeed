import type {Catalog} from './types';
import type {CockpitMetric,CockpitSnapshot,CockpitConclusion,CockpitScope} from './cockpitTypes';
import {dimensionBranch} from './dimensionTree';
import {locale,t} from './i18n';
import {qualityLabel} from './reportQuality';

export function cockpitAuxiliaryCategory(catalog:Catalog,focusCategoryId:string,scope?:CockpitScope):string|undefined{
 const members=scope?new Set(scope.nodeIds.flatMap(id=>[...dimensionBranch(catalog.records,id,scope.dimension,catalog.spaceSource==='fin')])):undefined;
 const meters=catalog.records.filter(row=>['meter','totalMeter'].includes(row.kind)&&row.pointId&&!row.canonicalId&&row.categoryId!==focusCategoryId&&(!members||members.has(String(row.id))));
 const water=meters.filter(meter=>catalog.records.some(point=>point.kind==='nativePoint'&&(point.id===meter.pointId||point.nativeSourceId===meter.pointId)&&Array.isArray(point.energyTags)&&point.energyTags.includes('water')));
 const categories=[...new Set(water.map(meter=>String(meter.categoryId)))];
 return categories.length===1?categories[0]:undefined;
}
export function cockpitCards(snapshot:CockpitSnapshot):CockpitMetric[]{
 const values=snapshot.modules.kpis?.data?.values||[];
 return ['cost','energy',values.some(value=>value.id==='auxiliaryEnergy')?'auxiliaryEnergy':'areaIntensity',values.some(value=>value.id==='activeAlarms')?'activeAlarms':'co2'].map(id=>values.find(value=>value.id===id)||{id,value:null,valueType:'null',valueBasis:'unavailable',unit:'',quality:'missing',sourceIds:[],reasonCodes:['MODULE_UNAVAILABLE']});
}
export function cockpitMetricTitle(id:string):string{
 switch(id){case 'cost':return t('关注能源费用');case 'energy':return t('关注能源用量');case 'auxiliaryEnergy':return t('辅助能源用量');case 'areaIntensity':return t('单位面积用量');case 'co2':return t('关注能源碳排放');case 'activeAlarms':return t('当前未恢复能耗事件');default:return t('驾驶舱指标');}
}
export function cockpitMetricValue(metric:Pick<CockpitMetric,'value'|'valueType'>):string{
 return metric.valueType==='na'?'NA':metric.valueType==='number'&&metric.value!=null&&Number.isFinite(metric.value)?new Intl.NumberFormat(locale,{maximumFractionDigits:3}).format(metric.value):'—';
}
export function cockpitReasonText(code:string):string{
 const labels:Record<string,string>={
  missingArea:t('未配置有效统计面积'),ambiguousArea:t('面积边界不明确，请引用服务空间'),missingTariff:t('未配置适用费率'),missingCoefficient:t('未配置折算系数'),missing:t('历史读数不足'),filtered:t('有效用量小计'),substituted:t('清洗后用量，含替代值'),
  CURRENT_UNAVAILABLE:t('本期没有可用数值'),REFERENCE_UNAVAILABLE:t('参照期没有可用数值'),INCOMPLETE_COVERAGE:t('两期覆盖不完整，不计算变化率'),INCOMPATIBLE_UNIT:t('两期单位或能源不兼容'),REPLACEMENT_HISTORY:t('包含替代值，不计算变化率'),ZERO_REFERENCE:t('参照期为零，百分比不可计算'),INCOMPATIBLE_CURRENCY:t('范围内币种不一致'),ACTIVE_EVENTS_UNAVAILABLE:t('当前事件状态不可用'),ACTIVE_EVENTS_READ_ERROR:t('当前事件状态读取失败'),LEAP_DAY_CLAMPED:t('闰日参照调整至二月末日'),TIMEZONE_OFFSET_CHANGED:t('两期时区偏移不同'),DURATION_DIFFERENCE:t('日历对齐后的两期时长不同'),LOCAL_TIME_ADJUSTED:t('不存在的当地时刻已按项目时区调整'),LOCAL_TIME_AMBIGUOUS:t('重复的当地时刻已按项目时区解析'),MODULE_UNAVAILABLE:t('本次快照未提供此指标'),partial:t('当前仅有部分有效用量'),historySampleLimit:t('历史样本超过当前查询上限，请缩小范围'),topologyIncomplete:t('计量关系尚未完整确认')
 };
 return labels[code]||qualityLabel(code);
}
export function cockpitComparisonText(metric:CockpitMetric):string{
 const comparison=metric.comparison;if(!comparison)return t('未启用同期比较');
 if(comparison.comparable&&comparison.changeRate!=null&&Number.isFinite(comparison.changeRate))return t('较参照期变化 {0}',new Intl.NumberFormat(locale,{maximumFractionDigits:2,signDisplay:'exceptZero'}).format(comparison.changeRate)+'%');
 return [...new Set(comparison.reasonCodes.map(cockpitReasonText))].join(t('；'))||t('两期数据不可比');
}
export function cockpitConclusionText(conclusion:CockpitConclusion):string{
 const args=conclusion.args;
 if(conclusion.messageKey==='cockpit.conclusion.dataQuality')return t('{0}受限：{1}',cockpitMetricTitle(String(args.metricId)),Array.isArray(args.reasonCodes)?args.reasonCodes.map(code=>cockpitReasonText(String(code))).join(t('；')):t('请核对数据来源与配置'));
 if(conclusion.messageKey==='cockpit.conclusion.activeEvents')return t('当前范围有 {0} 个未恢复能耗事件，状态观察于 {1}。',args.count,String(args.stateObservedAt||'—').replace('T',' '));
 if(conclusion.messageKey==='cockpit.conclusion.comparableChange'&&typeof args.changeRate==='number')return t('在两期完整且可比的范围内，关注能源用量变化 {0}；这不是核定节能收益。',new Intl.NumberFormat(locale,{maximumFractionDigits:2,signDisplay:'exceptZero'}).format(args.changeRate)+'%');
 return t('请展开查看此结论的规则与输入依据。');
}
