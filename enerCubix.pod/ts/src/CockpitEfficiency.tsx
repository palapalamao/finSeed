import {Alert,Button,Empty} from 'antd';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitCopSnapshot} from './cockpitEfficiencyProjection';
import {cockpitMetricValue,cockpitReasonText} from './cockpitMetrics';
import {ReportChart} from './ReportView';
import {locale,t} from './i18n';
export function CockpitEfficiency({snapshot,onOpen,name}:{snapshot:CockpitSnapshot;onOpen:(id:string)=>void;name:(id:string)=>string}){
 const items=snapshot.modules.efficiency?.data?.items||[];
 return <section className="cockpit-efficiency" aria-label={t('COP 能效')}><h3>{t('COP 能效')}</h3><p>{t('COP 按同一覆盖范围的供能总量除以输入能耗总量，不平均时段比值。')}</p>
 {!items.length?<Empty description={t('尚无适用的 COP 配置，请先关联同边界的供能量和输入能耗。')}/>:items.map(item=>{const report=cockpitCopSnapshot(snapshot,item.configId);return <section key={item.configId} data-cop={item.configId}><h4>{item.name}</h4><p className="cockpit-card-number">{cockpitMetricValue(item.ratio)} <small>COP</small></p><p>{t('供能总量 {0} {1} ÷ 输入能耗 {2} {3}',cockpitMetricValue(item.numerator),item.numerator.unit,cockpitMetricValue(item.denominator),item.denominator.unit)}</p>
 {item.ratio.value==null&&<Alert showIcon type="warning" message={(item.ratio.reasonCodes||[item.ratio.quality]).map(cockpitReasonText).join(t('；'))}/>}
 <p>{t('覆盖范围：{0}',item.coverageIds.map(name).join('、')||'—')}</p>
 {report&&<ReportChart snapshot={report}/>}
 <details><summary>{t('查看 COP 输入与时序')}</summary><dl><dt>{t('供能主点')}</dt><dd>{item.numerator.sourceIds.map(name).join('、')||'—'}</dd><dt>{t('输入能耗主点')}</dt><dd>{item.denominator.sourceIds.map(name).join('、')||'—'}</dd><dt>{t('配置版本')}</dt><dd>{item.configRef.mod||'—'}</dd></dl>
 {(item.actualEfficiency!==undefined||item.baselineEfficiency!==undefined)&&<p>{t('配置中的效率参考（非本次计算）：实际 {0}，基准 {1}',item.actualEfficiency??'—',item.baselineEfficiency??'—')}</p>}
 {report&&<div className="cockpit-table-scroll"><table><thead><tr><th>{t('时间')}</th><th>COP</th><th>{t('数据质量')}</th></tr></thead><tbody>{report.result.rows.map((row,index)=><tr key={index}><td>{String(row.ts||'—')}</td><td>{row.valueType==='na'?'NA':typeof row.value==='number'?new Intl.NumberFormat(locale,{maximumFractionDigits:3}).format(row.value):'—'}</td><td>{cockpitReasonText(String(row.quality||'missing'))}</td></tr>)}</tbody></table></div>}</details>
 <Button onClick={()=>onOpen(item.configId)}>{t('打开 COP 专业报告')}</Button></section>;})}</section>;
}
