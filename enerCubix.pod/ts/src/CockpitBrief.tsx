import {Button} from 'antd';
import {CockpitQuality} from './CockpitQuality';
import type {CockpitSnapshot} from './cockpitTypes';
import type {Catalog} from './types';
import {cockpitSpaceObjects,cockpitSpaceSites} from './cockpitSpaceProjection';
import {cockpitComparisonText,cockpitConclusionText,cockpitMetricValue,cockpitReasonText} from './cockpitMetrics';
import {t} from './i18n';
export function CockpitBrief({snapshot,catalog,onProfile,onFlow}:{snapshot:CockpitSnapshot;catalog:Catalog;onProfile:()=>void;onFlow:()=>void}){
 const cost=snapshot.modules.kpis?.data?.values.find(metric=>metric.id==='cost'),energy=snapshot.modules.kpis?.data?.values.find(metric=>metric.id==='energy'),nodes=cockpitSpaceObjects(snapshot,catalog),sites=cockpitSpaceSites(nodes),hero=cost?.valueType==='number'&&cost.value!==null?cost:energy,heroIsCost=hero?.id==='cost';
 return <section className="cockpit-brief" aria-label={t('能源经营简报')}><h2>{t('{0} · 能源经营简报',snapshot.context.project)}</h2><span>{t('同一快照：{0}',snapshot.snapshotId)}</span><div className="cockpit-brief-hero"><div><p>{heroIsCost?t('本期关注能源费用'):t('本期关注能源用量')}</p><strong className="cockpit-brief-number">{hero?cockpitMetricValue(hero):'—'} <small>{hero?.unit}</small></strong><p>{energy?cockpitComparisonText(energy):t('未启用同期比较')}</p>{heroIsCost&&<p>{t('按当前费率分析估算，非结算账单。')}</p>}{hero?.reasonCodes?.length?<p>{hero.reasonCodes.map(cockpitReasonText).join(t('；'))}</p>:null}<p>{t('未配置预算，不作预算达标判断。')}</p><div className="cockpit-drill-actions"><Button onClick={onProfile}>{t('打开专业趋势')}</Button><Button onClick={onFlow}>{t('打开完整能流')}</Button></div></div><div className="cockpit-brief-spaces" aria-label={t('实际空间对象')}>{sites.length?sites.map(({site,floors})=><div key={site.id}><strong>{site.name}</strong><div className="cockpit-brief-floors">{floors.map(floor=><span key={floor.id}>{floor.name}</span>)}</div></div>):<ul>{nodes.slice(0,6).map(node=><li key={node.id}>{node.name}<strong>{cockpitMetricValue(node)} {node.unit}</strong></li>)}</ul>}<p>{sites.length?t('按 FIN 真实站点与楼层示意，无实际比例；图与列表使用同一对象。'):t('当前范围无可用站点与楼层结构，显示真实对象列表，不生成虚构楼栋。')}</p></div></div><div className="cockpit-brief-quality"><CockpitQuality snapshot={snapshot}/></div></section>;
}
export function CockpitNextSteps({snapshot}:{snapshot:CockpitSnapshot}){
 const items=snapshot.modules.issues?.data?.items||[],conclusions=snapshot.modules.kpis?.data?.conclusions||[];
 return <section className="cockpit-next-steps" aria-label={t('下一步与数据说明')}><h3>{t('下一步与数据说明')}</h3><ol>{items.slice(0,3).map(item=><li key={item.id}><strong>{item.name||item.objectId}</strong><p>{item.type==='energyAlarm'?t('请核对事件小时证据，并在消息中心处理。'):t('请核对主能耗点、覆盖范围与配置依据。')}</p>{item.reasonCodes?.length?<p>{item.reasonCodes.map(cockpitReasonText).join(t('；'))}</p>:null}</li>)}</ol>{items.length===0&&<p>{t('当前范围没有可展示的重点事项')}</p>}{conclusions.slice(0,2).map(item=><p key={item.id}>{cockpitConclusionText(item)}</p>)}<p>{t('缺测与 NA 保留为空；已有用量不代表完整区间。')}</p></section>;
}
