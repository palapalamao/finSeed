import {useEffect,useRef,useState,type ReactNode} from 'react';
import {Alert,Button,Empty,Table} from 'antd';
import * as echarts from 'echarts/core';
import {PieChart} from 'echarts/charts';
import {GraphicComponent,LegendComponent,TooltipComponent} from 'echarts/components';
import {CanvasRenderer} from 'echarts/renderers';
import {t} from './i18n';
import {reportCellText} from './reportDisplay';
import {reportQualityText} from './reportQuality';
import {utilityChartOptions,utilityGroups,utilityName,utilityReason,type UtilityGroup,type UtilityRow} from './utility';
import type {ReportSnapshot} from './types';
import './utility.css';

echarts.use([PieChart,GraphicComponent,LegendComponent,TooltipComponent,CanvasRenderer]);
function UtilityChart({group,onSelect,exporting}:{group:UtilityGroup;onSelect:(id:string)=>void;exporting:boolean}){
 const host=useRef<HTMLDivElement>(null);
 useEffect(()=>{if(!host.current)return;const chart=echarts.init(host.current);chart.setOption(utilityChartOptions(group));chart.on('click',params=>{const data=params.data as {utilityId?:string}|undefined;if(!exporting&&data?.utilityId!==undefined)onSelect(data.utilityId);});const resize=new ResizeObserver(()=>chart.resize());resize.observe(host.current);return()=>{resize.disconnect();chart.dispose();};},[group,exporting,onSelect]);
 return <div className="utility-chart" ref={host} role="img" aria-label={t('所选表计的分项构成，详细数值见下方明细表')}/>;
}
function UtilityPanel({group,snapshot,exporting}:{group:UtilityGroup;snapshot:ReportSnapshot;exporting:boolean}){
 const[selected,setSelected]=useState<string>();
 useEffect(()=>setSelected(undefined),[snapshot]);
 const rows=selected===undefined||exporting?group.members:group.members.filter(row=>String(row.utilityId||'')===selected);
 const number=(row:UtilityRow)=>reportCellText(snapshot,'value',row.value,false,row);
 return <section className="utility-group" data-utility-group={group.key}>
  <h3>{group.title} · {t(group.unit)}</h3>
  {group.reason?<Alert type={group.reason==='overlappingScopes'?'error':'warning'} showIcon message={utilityReason(group.reason)}/>:<><p>{group.partial?t('已有用量占比；各表覆盖可能不同，不代表完整区间构成。'):t('按所选表计自身用量归入当前分项，同分项合并计算占比。')}</p><UtilityChart group={group} exporting={exporting} onSelect={setSelected}/><div className="utility-total">{t('已有用量合计')}：<strong>{group.total===null?'—':reportCellText(snapshot,'value',group.total)} {t(group.unit)}</strong></div></>}
  {!['overlappingScopes','areaNormalized','legacyUtilityShares'].includes(group.reason)&&<Table className="utility-share-table" size="small" pagination={false} scroll={{x:320}} rowKey={row=>String(row.id||row.utilityId||'unassigned')} dataSource={group.rows} columns={[{title:t('分项'),render:(_,row:UtilityRow)=><Button type="link" disabled={exporting} onClick={()=>setSelected(String(row.utilityId||''))}>{utilityName(row)}</Button>},{title:t('已有用量'),render:(_,row:UtilityRow)=>number(row)},{title:t('占比'),render:(_,row:UtilityRow)=>group.reason||typeof row.percentage!=='number'?'—':`${reportCellText(snapshot,'percentage',row.percentage)}${String(reportCellText(snapshot,'percentage',row.percentage)).includes('%')?'':'%'}`}]} />}
  <div className="table-heading"><h4>{t('各表自身用量与分项')}</h4>{selected!==undefined&&!exporting&&<Button size="small" onClick={()=>setSelected(undefined)} data-export-ignore="true">{t('显示全部表计')}</Button>}</div>
  <Table className="utility-member-table" size="small" pagination={false} scroll={{x:650}} rowKey={(row,index)=>String(row.nodeId||index)} dataSource={rows} columns={[{title:t('表计'),dataIndex:'name'},{title:t('所属分项'),render:(_,row:UtilityRow)=>utilityName(row)},{title:t('自身用量'),render:(_,row:UtilityRow)=>number(row)},{title:t('单位'),dataIndex:'unit'},{title:t('数据质量'),render:(_,row:UtilityRow)=>reportQualityText(snapshot,String(row.quality||'missing'))},{title:t('覆盖率'),render:(_,row:UtilityRow)=>typeof row.coverage==='number'?`${(row.coverage*100).toFixed(2)}%`:'—'}]} locale={{emptyText:t('此分项没有可显示的表计')}}/>
 </section>;
}
export function UtilityOverview({snapshot,exporting,trend}:{snapshot:ReportSnapshot;exporting:boolean;trend:ReactNode}){
 const groups=utilityGroups(snapshot);
 return <section className="utility-overview"><div className="profile-heading"><div><h3>{t('所选表计的分项构成')}</h3><p>{t('每块表读取自身主能耗点历史；总表不会自动展开分表。')}</p></div></div>{groups.length?groups.map(group=><UtilityPanel key={group.key} group={group} snapshot={snapshot} exporting={exporting}/>):<Empty description={t('此范围没有可显示的分项用量')}/>}<section className="utility-trend"><h3>{t('所选表计用量趋势')}</h3>{trend}</section></section>;
}
