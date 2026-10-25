import {useMemo,useState,type Key} from 'react';
import {Alert,Button,Pagination,Switch,Table,message} from 'antd';
import type {ReportSnapshot} from './types';
import {t} from './i18n';
import {numberText} from './reportDisplay';
import {reportQualityText} from './reportQuality';
import {coverageGroups,coverageDuration,coverageStatusText,type CoverageGroup,type CoveragePeriod} from './knownUsageCoverage';
import {exportCoverageXlsx} from './exports';
import './knownUsageCoverage.css';

const time=(value?:string)=>value?<time dateTime={value} title={value}>{value.replace('T',' ').slice(0,19)}</time>:'—';
function CoverageSource({group,snapshot}:{group:CoverageGroup;snapshot:ReportSnapshot}){
 const [issuesOnly,setIssuesOnly]=useState(true);
 const [expanded,setExpanded]=useState<readonly Key[]>([]);
 const issues=group.periods.filter(p=>!['complete','future','ongoing'].includes(p.status));
 const rows=issuesOnly?issues:group.periods;
 const value=(p:CoveragePeriod)=>p.valueType==='na'?'NA':p.value===null?'—':numberText(p.value);
 return <article className="usage-coverage-source">
  <div className="usage-coverage-source-heading"><h4>{group.name||t('对象名称不可用')}</h4><span>{t('源点：{0}',group.source||t('源点名称不可用'))} · {t(group.unit)}</span></div>
  <dl className="usage-coverage-summary"><div><dt>{t('有数值覆盖时长')}</dt><dd>{coverageDuration(group.coveredSeconds)}</dd></div><div><dt>{t('有数值记录范围')}</dt><dd className="usage-coverage-range">{time(group.firstReading)}<span aria-hidden="true"> — </span>{time(group.lastReading)}</dd></div></dl>
  {group.overlapping&&<Alert type="warning" showIcon message={t('覆盖记录存在重叠，保留各条记录，不重复合计时长。')}/>}
  <details className="usage-coverage-periods" data-export-ignore="true"><summary>{t('查看连续时段（{0} 段）',group.periods.length)}</summary>
   <div className="usage-coverage-controls"><p>{t('相邻且状态相同的记录已合并；时间沿用报告时区，结束时间不含。')}</p><label><Switch size="small" checked={issuesOnly} onChange={v=>{setIssuesOnly(v);setExpanded([]);}}/>{t('只看缺测与异常')}</label></div>
   {group.detailsTruncated&&<p className="usage-coverage-note" role="note">{t('原始区间仅返回 {0} 条明细；小计、区间数和覆盖时长仍按全部数据统计。',group.intervals.length)}</p>}
   <Table<CoveragePeriod> size="small" rowKey="key" className="usage-coverage-period-table" dataSource={rows} scroll={{x:720}} pagination={{pageSize:8,showSizeChanger:false,hideOnSinglePage:true}} locale={{emptyText:issuesOnly?t('没有缺测或异常时段。'):t('此范围没有覆盖记录。')}} columns={[
    {title:t('查询时段'),key:'range',render:(_,p)=><span className="usage-coverage-range">{time(p.from)}<span>—</span>{time(p.to)}</span>},
    {title:t('状态'),key:'status',render:(_,p)=><span className={`usage-coverage-status usage-coverage-${p.status}`} title={reportQualityText(snapshot,p.quality)}>{coverageStatusText(p.status)}</span>},
    {title:t('已有用量'),key:'value',align:'right',render:(_,p)=><span className="usage-coverage-number">{value(p)} {t(group.unit)}</span>},
    {title:t('有数值覆盖时长'),key:'covered',render:(_,p)=>coverageDuration(p.coveredSeconds)},
    {title:t('原始区间数'),key:'intervals',align:'right',render:(_,p)=>numberText(p.intervalCount)}
   ]} expandable={{expandedRowKeys:expanded,onExpandedRowsChange:keys=>setExpanded(keys.slice(-1)),rowExpandable:p=>p.intervalCount>0,expandedRowRender:p=><div className="usage-coverage-raw"><h5>{t('已返回的原始区间')}</h5><p>{p.detailsTruncated?t('部分原始明细未随本次报告返回，不代表缺测。'):t('以下为本次报告保存的原始区间。')}</p><Table size="small" rowKey={(r,i)=>`${r.intervalStart}-${i}`} dataSource={p.intervals} pagination={{pageSize:10,showSizeChanger:false,hideOnSinglePage:true}} scroll={{x:610}} locale={{emptyText:t('此时段的原始明细未随报告返回，请查看汇总或导出覆盖明细。')}} columns={[{title:t('区间开始'),dataIndex:'intervalStart',render:v=>time(v)},{title:t('区间结束（不含）'),dataIndex:'intervalEnd',render:v=>time(v)},{title:t('值'),key:'value',render:(_,r)=>r.valueType==='na'?'NA':r.value===null?'—':numberText(r.value)},{title:t('质量'),dataIndex:'quality',render:v=>reportQualityText(snapshot,v)}]}/></div>}}/>
  </details>
 </article>;
}
export function KnownUsageCoverage({snapshot,exporting=false}:{snapshot:ReportSnapshot;exporting?:boolean}){
 const groups=useMemo(()=>coverageGroups(snapshot),[snapshot]);const [page,setPage]=useState(1);const [busy,setBusy]=useState(false);
 if(!groups.length)return null;
 const selected=Math.min(page,Math.ceil(groups.length/5));
 const download=async()=>{setBusy(true);try{await exportCoverageXlsx(snapshot);}catch(e){message.error(e instanceof Error?e.message:t('导出失败'));}finally{setBusy(false);}};
 return <section className="usage-coverage" aria-label={t('用量覆盖')}>
  <div className="usage-coverage-heading"><div><h3>{t('用量覆盖')}</h3><p>{t('先看有数据的范围；连续缺测合并显示，原始记录按需展开。')}</p></div><Button size="small" onClick={()=>void download()} loading={busy} disabled={exporting} data-export-ignore="true">{t('导出覆盖明细')}</Button></div>
  {groups.slice((selected-1)*5,selected*5).map(group=><CoverageSource key={group.key} group={group} snapshot={snapshot}/>)}
  {groups.length>5&&<Pagination size="small" current={selected} pageSize={5} total={groups.length} showSizeChanger={false} onChange={setPage} data-export-ignore="true"/>}
  <p className="usage-coverage-foot">{t('按源点的原始区间统计时长，与上方按日或小时统计的时段数口径不同。缺测、NA 与未到时间分别保留。')}</p>
 </section>;
}
