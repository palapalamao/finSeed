import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitComparisonText,cockpitMetricValue,cockpitReasonText} from './cockpitMetrics';
import {t} from './i18n';
export function CockpitReference({snapshot}:{snapshot:CockpitSnapshot}){
 const metrics=snapshot.modules.kpis?.data?.values||[],energy=metrics.find(metric=>metric.id==='energy'),intensity=metrics.find(metric=>metric.id==='areaIntensity'),comparison=energy?.comparison;
 return <aside className="cockpit-reference" aria-label={t('经营参照')}><h3>{t('经营参照')}</h3><p>{comparison?t('参照期用量'):t('同期比较')}</p><strong className="cockpit-reference-number">{comparison?cockpitMetricValue({value:comparison.reference,valueType:comparison.reference==null?'null':'number'}):'—'} <small>{energy?.unit}</small></strong><p>{energy?cockpitComparisonText(energy):t('本次快照未提供此指标')}</p>{comparison&&<details><summary>{t('参照实际区间')}</summary><p>{comparison.referenceRange.from.replace('T',' ')} — {comparison.referenceRange.to.replace('T',' ')}</p>{comparison.reasonCodes.map(code=><p key={code}>{cockpitReasonText(code)}</p>)}</details>}{intensity&&<div className="cockpit-reference-intensity"><p>{t('单位面积用量')}</p><strong>{cockpitMetricValue(intensity)} {intensity.unit}</strong><p>{intensity.reasonCodes?.map(cockpitReasonText).join(t('；'))}</p></div>}<p className="cockpit-reference-budget">{t('未配置预算，不作预算达标判断。')}</p></aside>;
}
