import {useMemo,useState,type ReactNode} from 'react';
import {Alert,Button,Empty,Select} from 'antd';
import type {CockpitFace,CockpitHeatmapCell,CockpitSnapshot} from './cockpitTypes';
import type {ReportSnapshot} from './types';
import type {CockpitTargetKind} from './cockpitNavigation';
import {cockpitOrganizationReport,cockpitReferencedReport} from './cockpitReport';
import {ReportChart} from './ReportChart';
import {CockpitFlow} from './CockpitFlow';
import {CockpitEfficiency} from './CockpitEfficiency';
import {CockpitQuality} from './CockpitQuality';
import {CockpitShareChart} from './CockpitShareChart';
import {reportCellText,reportLabel} from './reportDisplay';
import {cockpitMetricValue,cockpitReasonText} from './cockpitMetrics';
import {locale,t} from './i18n';

const faceLabel=(face:CockpitFace)=>({space:t('空间'),time:t('时间'),endUse:t('用途'),organization:t('组织'),balance:t('计量平衡'),efficiency:t('能效')})[face];
function ReportRows({snapshot,name}:{snapshot:ReportSnapshot;name:(id:string)=>string}){
 const fields=['name','hour','value','knownValue','unit','quality','working','nonworking','knownWorking','knownNonworking','workingPercentage','knownPercentage','sourceIds'].filter(key=>snapshot.result.rows.some(row=>row[key]!==undefined));
 return <div className="cockpit-table-scroll"><table><thead><tr>{fields.map(field=><th key={field}>{reportLabel(snapshot,field)}</th>)}</tr></thead><tbody>{snapshot.result.rows.map((row,index)=><tr key={index}>{fields.map(field=><td key={field}>{field==='sourceIds'&&Array.isArray(row[field])?(row[field] as string[]).map(name).join('、'):field.endsWith('Percentage')&&typeof row[field]==='number'?new Intl.NumberFormat(locale,{maximumFractionDigits:2}).format(row[field])+'%':reportCellText(snapshot,field,row[field],false,row)}</td>)}</tr>)}</tbody></table></div>;
}
function Heatmap({cells,excluded,name}:{cells:CockpitHeatmapCell[];excluded:number;name:(id:string)=>string}){
 const series=[...new Set(cells.map(cell=>cell.seriesId))],months=[...new Set(cells.map(cell=>cell.date.slice(0,7)))].sort();
 const [chosenSeries,setChosenSeries]=useState(series[0]),[chosenMonth,setChosenMonth]=useState(months.at(-1)),[selected,setSelected]=useState<CockpitHeatmapCell>();
 const visible=cells.filter(cell=>cell.seriesId===(series.includes(chosenSeries)?chosenSeries:series[0])&&cell.date.startsWith(chosenMonth&&months.includes(chosenMonth)?chosenMonth:months.at(-1)||''));
 const days=[...new Set(visible.map(cell=>cell.date))].sort(),maximum=Math.max(0,...visible.map(cell=>Math.abs(cell.value)));
 return <section className="cockpit-heatmap"><h3>{t('完整日热力图')}</h3><p>{t('仅显示覆盖完整的当地日；缺测、NA、不完整日和未来时段不补零。')}</p>
  {excluded>0&&<p>{t('已排除 {0} 个不完整对象日，已有用量仍保留在趋势和明细中。',excluded)}</p>}
  {!visible.length?<Empty description={t('当前范围没有完整日可绘制热力图')}/>:<>
   <div className="cockpit-face-controls"><label>{t('热力图对象')}<Select aria-label={t('热力图对象')} value={series.includes(chosenSeries)?chosenSeries:series[0]} onChange={setChosenSeries} options={series.map(id=>({value:id,label:name(cells.find(cell=>cell.seriesId===id)!.nodeId)}))}/></label><label>{t('热力图月份')}<Select aria-label={t('热力图月份')} value={chosenMonth&&months.includes(chosenMonth)?chosenMonth:months.at(-1)} onChange={setChosenMonth} options={months.map(value=>({value,label:value}))}/></label></div>
   <div className="cockpit-heatmap-scroll">{days.map(day=>{const hours=visible.filter(cell=>cell.date===day);return <div className="cockpit-heatmap-day" key={day}><strong>{day}</strong><div style={{gridTemplateColumns:`repeat(${hours.length},minmax(36px,1fr))`}}>{hours.map(cell=><button type="button" key={cell.ts} style={{background:`rgba(52,136,178,${.12+(maximum?Math.abs(cell.value)/maximum:0)*.75})`}} aria-label={t('{0}：{1} {2}',cell.ts,cell.value,cell.unit)} onClick={()=>setSelected(cell)}><span>{String(cell.hour).padStart(2,'0')}</span><small>{cockpitMetricValue({value:cell.value,valueType:'number'})}</small></button>)}</div></div>;})}</div>
   <p aria-live="polite">{selected?t('所选时段 {0}：{1} {2}',selected.ts,selected.value,selected.unit):t('点击时段可查看绝对时间及数值，重复小时分别保留。')}</p>
   <details><summary>{t('查看热力图数值表')}</summary><div className="cockpit-table-scroll"><table><thead><tr><th>{t('时间')}</th><th>{t('值')}</th><th>{t('单位')}</th></tr></thead><tbody>{visible.map(cell=><tr key={cell.ts}><td>{cell.ts}</td><td>{cockpitMetricValue({value:cell.value,valueType:'number'})}</td><td>{cell.unit}</td></tr>)}</tbody></table></div></details>
  </>}
 </section>;
}
export function CockpitMain({snapshot,face,onFace,onReport,name,focusObjectId,onFlow,onCop,space,reference,issues}:{space:ReactNode;reference:ReactNode;issues:ReactNode;onCop:(id:string)=>void;focusObjectId?:string;onFlow:()=>void;snapshot:CockpitSnapshot;face:CockpitFace;onFace:(face:CockpitFace)=>void;onReport:(kind:Exclude<CockpitTargetKind,'energyFlow'>)=>void;name:(id:string)=>string}){
 const faces:CockpitFace[]=['space',...(['time','endUse','organization','efficiency','balance'] as const).filter(id=>snapshot.capabilities.availableFaces.includes(id))];
 const daily=useMemo(()=>snapshot.modules.time?.data?cockpitReferencedReport(snapshot,snapshot.modules.time.data.dailyReportRef):undefined,[snapshot,locale]);
 const utility=useMemo(()=>snapshot.modules.endUse?.data?cockpitReferencedReport(snapshot,snapshot.modules.endUse.data.reportRef):undefined,[snapshot,locale]);
 const shareReport=useMemo(()=>utility?{...utility,result:{...utility.result,rows:((utility.result.extra?.utilityShares||[]) as Record<string,unknown>[]).map<Record<string,unknown>>(row=>({...row,name:row.utilityId?row.name:t('未指定分项')}))}}:undefined,[utility,locale]);
 const organization=useMemo(()=>cockpitOrganizationReport(snapshot),[snapshot,locale]);
 const module=face==='space'?undefined:snapshot.modules[face];
 const working=[snapshot.modules.time?.data?.workingReportRef,snapshot.modules.time?.data?.workingDaysReportRef].flatMap(ref=>ref?[cockpitReferencedReport(snapshot,ref)].filter((report):report is ReportSnapshot=>!!report):[]);
 return <section className="cockpit-main" aria-label={t('驾驶舱分析视角')}>
  <div className="cockpit-face-heading"><h3>{t('分析视角')}</h3><div className="cockpit-face-tabs" role="tablist" aria-label={t('驾驶舱分析视角')}>{faces.map((value,index)=><button type="button" role="tab" key={value} id={'cockpit-tab-'+value} aria-selected={face===value} aria-controls={'cockpit-panel-'+value} tabIndex={face===value?0:-1} onClick={()=>onFace(value)} onKeyDown={event=>{let next=index;if(event.key==='ArrowRight')next=(index+1)%faces.length;else if(event.key==='ArrowLeft')next=(index+faces.length-1)%faces.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=faces.length-1;else return;event.preventDefault();document.getElementById('cockpit-tab-'+faces[next])?.focus();}}>{faceLabel(value)}</button>)}</div></div>
  <div className="cockpit-workbench">{reference}<div className="cockpit-visual">{face==='space'&&<div role="tabpanel" id="cockpit-panel-space" aria-labelledby="cockpit-tab-space">{space}</div>}
  {face!=='space'&&<div className="cockpit-face-panel" data-face={face} role="tabpanel" id={'cockpit-panel-'+face} aria-labelledby={'cockpit-tab-'+face}>
   {!!module?.reasonCodes?.length&&<Alert showIcon type="info" message={[...new Set(module.reasonCodes.map(cockpitReasonText))].join(t('；'))}/>}
   {!module?.data?<Empty description={module?.status==='error'?t('该视角暂时不可用，请刷新后重试。'):t('当前快照未提供此视角，请刷新查询。')}/>:<>
    {face==='efficiency'&&<CockpitEfficiency snapshot={snapshot} onOpen={onCop} name={name}/>}
    {face==='balance'&&<CockpitFlow snapshot={snapshot} focusObjectId={focusObjectId} onOpen={onFlow}/>}
    {face==='time'&&daily&&<><h3>{t('各小时平均用量')}</h3><p>{t('显示每小时平均能量，单位沿用主点能量单位；不等同于瞬时功率。')}</p><ReportChart snapshot={daily} profileType="line"/><details><summary>{t('查看小时均值明细')}</summary><ReportRows name={name} snapshot={daily}/></details><Button onClick={()=>onReport('daily')}>{t('打开日均用量报告')}</Button><Heatmap key={snapshot.snapshotId} cells={snapshot.modules.time!.data!.heatmap} excluded={snapshot.modules.time!.data!.excludedDays.length} name={name}/>{working.map(report=><details key={report.result.kind}><summary>{report.title}</summary><ReportRows name={name} snapshot={report}/><Button onClick={()=>onReport(report.result.kind as 'workingHours'|'workingDays')}>{t('打开对应专业报告')}</Button></details>)}</>}
    {face==='endUse'&&utility&&shareReport&&<><h3>{t('用途分布')}</h3><p>{t('只按本次有效表计集合的用途属性归组；未指定用途单列，不将物理差额当作用途。')}</p><p>{t('构成基于已有用量，不代表完整区间。')}</p>{!snapshot.modules.endUse!.data!.additive?<Alert type="warning" showIcon message={t('范围包含共享或重叠来源，不计算构成占比；请改选互不重叠的表计。')}/>:shareReport.result.rows.some(row=>typeof row.knownPercentage==='number'&&row.knownPercentage>0)?<CockpitShareChart snapshot={shareReport} name={name}/>:<Alert type="info" showIcon message={t('总量为零或没有可用占比，保留分项数值。')}/>}<ReportRows name={name} snapshot={shareReport}/><details><summary>{t('查看分项表计明细')}</summary><ReportRows name={name} snapshot={utility}/></details><Button onClick={()=>onReport('utility')}>{t('打开分项用量报告')}</Button></>}
    {face==='organization'&&organization&&<><h3>{t('组织分布')}</h3><p>{t('父组织包含子组织，不将各层级重复合计；未指定组织的用量单列。')}</p>{snapshot.modules.organization!.data!.additive?<ReportChart snapshot={organization} compact/>:<Alert type="warning" showIcon message={t('范围重叠，保留组织和表计明细，不显示可相加的分布。')}/>}<div className="cockpit-table-scroll"><table><thead><tr><th>{t('组织')}</th><th>{t('上级组织')}</th><th>{t('已有用量')}</th><th>{t('完整区间用量')}</th><th>{t('单位')}</th><th>{t('数据质量')}</th><th>{t('计量对象')}</th></tr></thead><tbody>{snapshot.modules.organization!.data!.nodes.map(node=><tr key={node.id}><td>{node.nodeKind==='unassigned'?t('未指定组织'):node.name}</td><td>{snapshot.modules.organization!.data!.nodes.find(parent=>parent.id===node.parentId)?.name||'—'}</td><td>{cockpitMetricValue(node)}</td><td>{cockpitMetricValue({value:node.completeValue,valueType:node.completeValue==null?'null':'number'})}</td><td>{node.unit}</td><td>{cockpitReasonText(node.quality)}</td><td>{node.meterIds.map(name).join('、')}</td></tr>)}</tbody></table></div><Button onClick={()=>onReport('profile')}>{t('查看范围表计明细')}</Button></>}
    <p>{t('专业页对应当前区间；同期比较在驾驶舱卡片查看。')}</p>
   </>}
  </div>}
 <CockpitQuality snapshot={snapshot}/></div><aside className="cockpit-checks">{issues}</aside></div>
 </section>;
}
