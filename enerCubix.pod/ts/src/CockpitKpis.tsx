import {Tag} from 'antd';
import type {CockpitMetric,CockpitSnapshot} from './cockpitTypes';
import {cockpitCards,cockpitComparisonText,cockpitConclusionText,cockpitMetricTitle,cockpitMetricValue,cockpitReasonText} from './cockpitMetrics';
import {locale,t} from './i18n';

function basis(metric:CockpitMetric):string{
 if(metric.valueBasis==='currentState')return t('当前状态，不代表历史区间');
 if(metric.valueBasis==='unavailable')return t('暂无有效数值');
 if(metric.valueBasis==='cleanedWithReplacement')return t('清洗后用量，含替代值');
 if(metric.valueBasis==='knownSubtotal')return metric.id==='cost'?t('已有费用小计'):t('有效用量小计');
 return metric.id==='cost'?t('完整区间费用'):metric.id==='co2'?t('完整区间碳排放'):metric.id==='areaIntensity'?t('完整区间单位面积用量'):t('完整区间用量');
}
const time=(value:string)=>value.replace('T',' ');
export function CockpitKpis({snapshot,name}:{snapshot:CockpitSnapshot;name:(id:string)=>string}){
 const metrics=cockpitCards(snapshot),conclusions=snapshot.modules.kpis?.data?.conclusions||[];
 return <>
  {conclusions.length>0&&<section className="cockpit-conclusions" aria-label={t('管理结论')}><h3>{t('管理结论')}</h3>{conclusions.slice(0,2).map(conclusion=><div key={conclusion.id}><p>{cockpitConclusionText(conclusion)}</p><details><summary>{t('查看结论依据')}</summary><dl><dt>{t('计算规则')}</dt><dd>{t('{0}，版本 {1}',conclusion.ruleId,conclusion.ruleVersion)}</dd><dt>{t('来源引用')}</dt><dd>{conclusion.evidenceRefs.map(name).join('、')||'—'}</dd></dl><pre>{JSON.stringify(conclusion.args,null,2)}</pre></details></div>)}</section>}
  <section className="cockpit-kpis" aria-label={t('核心经营指标')}>
   {metrics.map(metric=><section key={metric.id} className={'cockpit-kpi'+(metric.id==='energy'?' cockpit-energy':'')} data-metric={metric.id} aria-label={cockpitMetricTitle(metric.id)}>
    <h3>{cockpitMetricTitle(metric.id)}</h3>
    {metric.id==='auxiliaryEnergy'&&metric.categoryId&&<p className="cockpit-card-category">{name(metric.categoryId)}</p>}
    <p className={metric.id==='energy'?'cockpit-number':'cockpit-card-number'}>{cockpitMetricValue(metric)} <small>{metric.unit==='count'?t('个'):metric.unit}</small></p>
    <Tag color={['complete','currentState'].includes(metric.valueBasis)?'green':'gold'}>{basis(metric)}</Tag>
    {metric.id==='cost'&&<p>{t('按当前费率分析估算，非结算账单。')}</p>}
    {metric.id==='activeAlarms'?<p>{t('状态观察：{0}',metric.stateObservedAt?time(metric.stateObservedAt):t('暂无数据'))}</p>:<p className="cockpit-card-comparison">{cockpitComparisonText(metric)}</p>}
    {metric.reasonCodes&&metric.reasonCodes.length>0&&<p className="cockpit-card-reasons">{[...new Set(metric.reasonCodes.map(cockpitReasonText))].join(t('；'))}</p>}
    <details className="cockpit-card-details"><summary>{t('查看指标依据')}</summary>
     {metric.comparison&&<dl><dt>{t('本期实际区间')}</dt><dd>{time(metric.comparison.currentRange.from)} — {time(metric.comparison.currentRange.to)}</dd><dt>{t('参照实际区间')}</dt><dd>{time(metric.comparison.referenceRange.from)} — {time(metric.comparison.referenceRange.to)}</dd><dt>{t('本期数值')}</dt><dd>{cockpitMetricValue({value:metric.comparison.current,valueType:metric.comparison.current==null?'null':'number'})} {metric.unit}</dd><dt>{t('参照期数值')}</dt><dd>{cockpitMetricValue({value:metric.comparison.reference,valueType:metric.comparison.reference==null?'null':'number'})} {metric.unit}</dd><dt>{t('两期时长差（秒）')}</dt><dd>{metric.comparison.durationDifferenceSeconds}</dd></dl>}
     {!!metric.comparison?.reasonCodes.length&&<p>{metric.comparison.reasonCodes.map(cockpitReasonText).join(t('；'))}</p>}
     <dl><dt>{t('来源引用')}</dt><dd>{metric.sourceIds.map(name).join('、')||'—'}</dd></dl>
     {metric.coverage?.map((coverage,index)=><p key={String(coverage.id||index)}>{t('{0}：覆盖率 {1}',name(String(coverage.nodeId||coverage.id||'—')),typeof coverage.coverage==='number'?new Intl.NumberFormat(locale,{style:'percent',maximumFractionDigits:1}).format(coverage.coverage):'—')}</p>)}
     {metric.details&&<details><summary>{t('查看计算配置快照')}</summary><pre>{JSON.stringify(metric.details,null,2)}</pre></details>}
    </details>
   </section>)}
  </section>
 </>;
}
