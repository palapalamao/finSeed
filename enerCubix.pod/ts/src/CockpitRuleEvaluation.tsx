import type {RuleEvaluation} from './cockpitConfig';
import {configNumber} from './cockpitConfig';
import {cockpitReasonText} from './cockpitMetrics';
import {t} from './i18n';
import './cockpitConfig.css';
export const ruleTitle=(type:RuleEvaluation['ruleType'])=>type==='budgetVariance'?t('预算偏差线索'):t('非工作时段高用量线索');
export function RuleEvaluationDetails({evaluation,name,open=false}:{evaluation:RuleEvaluation;name:(id:string)=>string;open?:boolean}){
 const e=evaluation,inputs=e.inputs||{},c=e.configuration;
 const fields:Record<string,string>={periodActualCost:t('期间费用'),periodBudget:t('期间预算'),deviationAmount:t('超出金额'),variancePct:t('期间偏差 (%)'),normalizedThreshold:t('标准化用量阈值'),nonWorkingHours:t('非工作小时数'),validNonWorkingHours:t('有效完整小时数'),unavailableNonWorkingHours:t('不可用小时数'),triggerCount:t('触发小时数')};
 return <details className="cockpit-rule-evaluation" open={open}><summary>{t('规则评估：{0} · {1}',c?.name||ruleTitle(e.ruleType),({triggered:t('已触发线索'),notTriggered:t('未触发'),unavailable:t('无法判定'),disabled:t('已停用')} as Record<string,string>)[e.status]||t('无法判定'))}</summary>{e.ruleType==='budgetVariance'&&e.status==='triggered'&&<section className="cockpit-budget-pressure"><p>{t('期间费用高于期间预算 {0}%，请核对用量、费率和预算安排。',configNumber(typeof inputs.variancePct==='number'?inputs.variancePct:null))}</p><div className="cockpit-budget-values">{[['期间费用',inputs.periodActualCost],['期间预算',inputs.periodBudget],['超出金额',inputs.deviationAmount]].map(([label,value])=><div key={String(label)}><p>{t(String(label))}</p><strong>{configNumber(typeof value==='number'?value:null)} <small>{String(inputs.currency||'')}</small></strong></div>)}</div></section>}<p>{t('规则只生成核查线索，不创建、确认或恢复 FIN Alarm，也不推断设备运行原因。')}</p>
 {!!e.reasonCodes?.length&&<p>{e.reasonCodes.map(cockpitReasonText).join(t('；'))}</p>}
 {e.ruleType==='nonWorkingHighUsage'&&<p>{t('仅使用完整且质量合格的主点小时判断；含替代值的小时不参与触发。替代小时与存在未核实来源的小时可能重叠，不能相加。')}</p>}
 <dl><dt>{t('规则类型')}</dt><dd>{ruleTitle(e.ruleType)}</dd><dt>{t('规则版本')}</dt><dd>{e.profileRef?.version??'—'} / {e.profileRef?.mod||'—'}</dd><dt>{t('适用范围')}</dt><dd>{c?.scopeKind==='project'?t('整个 FIN 项目'):c?.scopeRef?name(c.scopeRef):t('关联对象不可用')}</dd><dt>{t('能源分类')}</dt><dd>{c?.categoryRef?name(c.categoryRef):'—'}</dd><dt>{t('证据区间')}</dt><dd>{e.triggerFrom||e.from} — {e.triggerTo||e.to}</dd><dt>{t('查询截止')}</dt><dd>{e.asOf}</dd><dt>{t('比较符')}</dt><dd>{t('大于（>），等于阈值不触发')}</dd><dt>{t('规则阈值')}</dt><dd>{configNumber(e.threshold)} {e.thresholdUnit}</dd>
 {Object.entries(fields).filter(([key])=>Object.hasOwn(inputs,key)).map(([key,label])=><span className="cockpit-rule-input" key={key}><dt>{label}</dt><dd>{typeof inputs[key]==='number'?configNumber(inputs[key] as number):'—'}{key==='variancePct'?'%':''}</dd></span>)}
 {e.ruleType==='nonWorkingHighUsage'&&[['substitutedNonWorkingHours','已观察到替代值的小时数'],['unknownSubstitutionNonWorkingHours','替代情况未完整核实的小时数']].map(([key,label])=><span className="cockpit-rule-substitution" key={key}><dt>{t(label)}</dt><dd>{typeof inputs[key]==='number'?configNumber(inputs[key] as number):t('此快照未提供')}</dd></span>)}
 {c?.calendarRef&&<><dt>{t('运行日历')}</dt><dd>{name(c.calendarRef)}</dd></>}<dt>{t('币种')}</dt><dd>{String(inputs.currency||c?.currency||'—')}</dd><dt>{t('源点')}</dt><dd>{e.sourceIds?.map(name).join(' / ')||'—'}</dd></dl>
 <p>{e.ruleType==='budgetVariance'?t('请核对预算曲线、费用口径、计费规则及主要用量变化。'):t('请核对日历、小时用量、数据覆盖与现场运行记录，不能仅据此确定原因。')}</p>
 <details open={open}><summary>{t('技术依据（配置、输入与公式）')}</summary><pre>{JSON.stringify({profileRef:e.profileRef,configuration:e.configuration,calendar:e.calendar,inputs:e.inputs,formula:e.formula},null,2)}</pre></details></details>;
}
