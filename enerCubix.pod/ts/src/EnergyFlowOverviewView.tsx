import {t,locale} from './i18n';
import {energyFlowOverview} from './energyFlow';
import {numberText} from './reportDisplay';
import {reportQualityText} from './reportQuality';
import type {ReportSnapshot} from './types';

export function EnergyFlowOverviewView({snapshot}:{snapshot:ReportSnapshot}){
 const data=energyFlowOverview(snapshot.result);if(!data)return null;
 const duration=(seconds:number)=>t('{0} 小时',numberText(seconds/3600));
 const time=(value:string)=>new Date(value).toLocaleString(locale,{year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit'});
 return <section className="energy-flow-view" aria-label={t('全区间总览')}>
  <div className="energy-flow-heading"><div><h3>{t('全区间总览')}</h3><p>{t('每块表独立读取自身历史，总表与分表不相加。选择时段可查看当时的能流与计量差额。')}</p></div></div>
  {data.unknownTopologySeconds>0&&<div className="energy-flow-notices" role="status"><strong>{t('历史计量关系尚未确认')}</strong><p>{t('其中 {0} 的计量关系未知；保留各表自身用量，不推定流向或差额。',duration(data.unknownTopologySeconds))}</p></div>}
  <div className="energy-flow-table-scroll"><table className="energy-flow-table"><thead><tr><th>{t('计量对象')}</th><th>{t('统计口径')}</th><th>{t('用量')}</th><th>{t('有效时长 / 纳入时长')}</th><th>{t('覆盖率')}</th><th>{t('数据质量')}</th></tr></thead><tbody>{data.rows.map(row=><tr key={row.id} data-overview-meter={row.id}><th scope="row">{row.name}{row.removed&&<small className="energy-flow-balance-quality">{t('历史成员（已移除）')}</small>}</th><td>{row.substituted?t('清洗后用量，含替代值'):row.complete?t('区间用量'):t('有效用量小计')}</td><td className="energy-flow-numeric">{row.quality==='na'?'NA':row.value===null?'—':numberText(row.value)} {t(row.unit)}</td><td>{duration(row.coveredSeconds)} / {duration(row.activeSeconds)}</td><td>{numberText(row.coverage*100)}%</td><td>{reportQualityText(snapshot,row.quality)}<details><summary>{t('查看覆盖时段与缺口')}</summary>{row.periods.map((period,index)=><p key={index}>{time(period.from)} — {time(period.to)} · {reportQualityText(snapshot,period.quality)}{period.value!==null?` · ${numberText(period.value)} ${t(row.unit)}`:''}</p>)}</details></td></tr>)}</tbody></table></div>
  {!data.rows.length&&<p>{t('此时段没有纳入所选范围的表计。')}</p>}
  <p className="energy-flow-table-foot">{t('缺测与 NA 不补零，过滤后的有限数值保留。基础用量按表计自身历史和有效主点读取；计量关系只用于成员展示与分段平衡，源区间不按比例拆分。')}</p>
 </section>;
}
