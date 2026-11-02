import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitReasonText} from './cockpitMetrics';
import {t} from './i18n';
export function CockpitQuality({snapshot}:{snapshot:CockpitSnapshot}){
 const names:Record<string,string>={kpis:t('核心经营指标'),space:t('空间'),trend:t('用量趋势'),time:t('时间'),endUse:t('用途'),organization:t('组织'),balance:t('计量平衡'),efficiency:t('能效'),issues:t('重点事项')};
 const statuses={ok:t('正常'),partial:t('部分数据可用'),empty:t('暂无数据'),unavailable:t('暂不可用'),error:t('读取失败')};
 const modules=Object.entries(snapshot.modules),limited=modules.filter(([,module])=>module.status!=='ok');
 return <section className="cockpit-quality-summary" aria-label={t('模块质量摘要')}><p><strong>{t('数据质量')}</strong> · {limited.length?t('{0} 个模块需要关注；其余有效结果保留。',limited.length):t('已返回模块均正常。')}{!snapshot.boundary.aggregateAllowed&&' '+t('统计边界存在重叠，不能将各对象直接相加。')}</p><details><summary>{t('查看模块质量与诊断')}</summary>{modules.map(([key,module])=><p key={key}><strong>{names[key]||key}</strong>：{statuses[module.status]} {(module.reasonCodes||[]).map(cockpitReasonText).join(t('；'))}</p>)}<details><summary>{t('查看覆盖与清洗依据')}</summary><p>{t('源点：{0}',snapshot.boundary.sourcePointIds.join(' / ')||'—')}</p><pre>{JSON.stringify({coverage:snapshot.quality,cleaning:snapshot.provenance.appliedCleaning??null},null,2)}</pre></details>{snapshot.limitations.length>0&&<p>{snapshot.limitations.map(cockpitReasonText).join(t('；'))}</p>}</details></section>;
}
