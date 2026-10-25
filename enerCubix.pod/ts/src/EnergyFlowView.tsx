import {useId,useMemo} from 'react';
import {Tooltip} from 'antd';
import {ReportMeterOriginBadge} from './MeterOriginBadge';
import {locale,t} from './i18n';
import {energyFlowBreadcrumbs,energyFlowData,energyFlowFocus,energyFlowLayout,energyFlowStats,type EnergyFlowLink,type EnergyFlowNode} from './energyFlow';
import type {ReportSnapshot} from './types';
import './energyFlow.css';

const formatter=new Intl.NumberFormat(locale,{maximumFractionDigits:2});
const percentageFormatter=new Intl.NumberFormat(locale,{maximumFractionDigits:1});
const valueText=(value:number|null)=>value!==null&&Number.isFinite(value)?formatter.format(value):'—';
const nodeLabel=(node:EnergyFlowNode)=>node.nodeType==='summary'?t('能源汇总'):node.nodeType==='difference'?node.balanceMode==='consistency'?t('计算差额'):t('计量差额'):node.name;
const percentageText=(value:number|null,percentage:number|null)=>value!==null&&value!==0&&percentage!==null&&Number.isFinite(percentage)?`${percentageFormatter.format(percentage)}%`:'—';
const shareText=(node:EnergyFlowNode)=>percentageText(node.value,node.percentage);
const qualityText=(quality:string)=>({ok:t('完整'),good:t('完整'),derived:t('计算值'),estimated:t('估算值'),cleaned:t('已清洗'),corrected:t('回绕已修正'),substituted:t('含替代值'),filtered:t('有效用量小计'),na:'NA',missing:t('缺测'),negativeBalance:t('分表大于总表'),topologyIncomplete:t('计量关系不完整'),topologyUnknown:t('历史计量关系尚未确认'),invalid:t('无效数据'),negative:t('无效数据'),zero:t('零用量'),leaf:t('计量终点'),notApplicable:t('不适用')} as Record<string,string>)[quality]||t('其他质量（{0}）',quality);
const sourceText=(snapshot:ReportSnapshot,ids:string[])=>ids.map(id=>snapshot.display?.sources[id]||id).join(', ')||t('未提供');
const drillable=(node:EnergyFlowNode)=>node.nodeType==='meter'&&node.hasChildren;

function FlowTooltip({snapshot,node,link}:{snapshot:ReportSnapshot;node:EnergyFlowNode;link?:EnergyFlowLink}){
 return <div className="energy-flow-tooltip"><strong>{nodeLabel(node)}</strong><ReportMeterOriginBadge snapshot={snapshot} id={node.id}/><dl><div><dt>{t('区间用量')}</dt><dd>{valueText(link?.value??node.value)} {t(node.unit)}</dd></div><div><dt>{t('占直接上级')}</dt><dd>{link?percentageText(link.value,link.percentage):shareText(node)}</dd></div><div><dt>{t('数据质量')}</dt><dd>{qualityText(link?.quality??node.quality)}</dd></div>{node.hasChildren&&<div><dt>{t('计量平衡')}</dt><dd>{qualityText(node.balanceQuality)}</dd></div>}<div><dt>{t('源点')}</dt><dd>{sourceText(snapshot,link?.sourceIds??node.sourceIds)}</dd></div></dl><p>{node.nodeType==='summary'?t('统计汇总，非实测总表'):node.nodeType==='difference'?t('总表减直属分表合计'):drillable(node)?t('查看下一级'):t('当前计量终点')}</p></div>;
}

function FlowDetails({snapshot,nodes,onFocus,exporting,unassigned=false}:{snapshot:ReportSnapshot;nodes:EnergyFlowNode[];onFocus:(id:string)=>void;exporting:boolean;unassigned?:boolean}){
 const data=energyFlowData(snapshot.result)!;const byId=new Map([...energyFlowBreadcrumbs(snapshot),...data.nodes].map(node=>[node.id,node]));
 return <div className="energy-flow-table-scroll"><table className="energy-flow-table"><thead><tr><th scope="col">{t('计量对象')}</th><th scope="col">{t('上级对象')}</th><th scope="col" className="energy-flow-numeric">{t('用量（{0}）',t(data.unit))}</th><th scope="col" className="energy-flow-numeric">{t('占上级比例')}</th><th scope="col">{t('数据质量')}</th><th scope="col">{t('源点')}</th></tr></thead><tbody>{nodes.map(node=>{const parent=node.parentId?byId.get(node.parentId):undefined;return <tr key={node.id} data-flow-row={node.id}><th scope="row">{drillable(node)?<button type="button" className="energy-flow-table-node" disabled={exporting} onClick={()=>onFocus(node.id)}>{nodeLabel(node)}<span aria-hidden="true">›</span></button>:<span className={node.nodeType==='difference'?'energy-flow-muted':undefined}>{nodeLabel(node)}</span>}<ReportMeterOriginBadge snapshot={snapshot} id={node.id}/></th><td>{unassigned?t('未归属'):parent?nodeLabel(parent):data.rootIds.includes(node.id)&&node.nodeType==='meter'?t('能源汇总'):'—'}</td><td className="energy-flow-numeric">{valueText(node.value)}</td><td className="energy-flow-numeric">{unassigned?'—':shareText(node)}</td><td><span className={`energy-flow-quality${node.nodeType==='difference'?' energy-flow-quality-derived':node.value===null||!['ok','good','derived','estimated'].includes(node.quality)?' energy-flow-quality-warning':''}`}>{qualityText(node.quality)}</span>{node.hasChildren&&!['ok','good','derived','estimated'].includes(node.balanceQuality)&&<small className="energy-flow-balance-quality">{qualityText(node.balanceQuality)}</small>}</td><td className="energy-flow-source">{sourceText(snapshot,node.sourceIds)}</td></tr>;})}</tbody></table></div>;
}

export function EnergyFlowView({snapshot,onFocus,exporting}:{snapshot:ReportSnapshot;onFocus:(id:string)=>void;exporting:boolean}){
 const titleId=useId(),descriptionId=useId(),detailsId=useId();
 const data=energyFlowData(snapshot.result);
 const layout=useMemo(()=>data?energyFlowLayout(data):undefined,[data]);
 if(!data||!layout)return <section className="energy-flow-empty"><h3>{t('尚无能流数据')}</h3><p>{t('当前服务未返回能流数据，请重新查询。')}</p></section>;
 const focus=energyFlowFocus(data);if(!focus)return <section className="energy-flow-empty"><h3>{t('尚无能流数据')}</h3></section>;
 const stats=energyFlowStats(data);const breadcrumbs=energyFlowBreadcrumbs(snapshot);const category=snapshot.display?.objects[data.categoryId]||snapshot.categoryNames?.[0]||t('能源汇总');const unit=t(data.unit);
 const legend=layout.nodes.filter(node=>stats.overview?node.depth===1:node.depth===0);
 const anomalies=data.nodes.filter(node=>node.nodeType!=='difference'&&(node.value===null||node.hasChildren&&!['ok','good','derived','estimated','cleaned','corrected'].includes(node.balanceQuality)));
 const consistency=data.nodes.some(node=>node.balanceMode==='consistency');
 const unknownTopology=data.nodes.some(node=>node.balanceQuality==='topologyUnknown');
 const unknownBasis=data.nodes.some(node=>node.hasChildren&&node.balanceMode==='unknown');
 const tableNodes=data.nodes.filter(node=>node.nodeType!=='summary');const byId=new Map(layout.nodes.map(node=>[node.node.id,node]));
 const share=(value:number|null)=>value!==null&&stats.total!==null&&stats.total>0?t('占当前用量 {0}%',percentageFormatter.format(value/stats.total*100)):t('用量为零或缺测时不计算比例');
 const heading=stats.overview?[t('能源汇总'),t('总表'),t('直属分表')]:[t('当前表计'),t('下级分表'),t('下一级去向')];
 return <section className="energy-flow-view" aria-label={t('能流图')}>
  <div className="energy-flow-heading"><div><h3>{t('{0}能流',stats.overview?category:nodeLabel(focus))}</h3><p>{t('图中节点与流线均使用实际区间用量，未归属表计另列。')}</p></div><button type="button" className="energy-flow-back" disabled={stats.overview||exporting} onClick={()=>onFocus('')} data-export-ignore="true"><span aria-hidden="true">←</span>{t('返回概览')}</button></div>
  {consistency&&<div className="energy-flow-notices" role="status"><strong>{t('计算一致性检查')}</strong><p>{t('虚拟合计与其来源的差额不能用于证明没有泄漏。')}</p></div>}
  {unknownTopology&&<div className="energy-flow-notices" role="status"><strong>{t('历史计量关系尚未确认')}</strong><p>{t('保留表计自身历史，不使用当前关系推定过去的流向或差额。')}</p></div>}
  {unknownBasis&&!unknownTopology&&<div className="energy-flow-notices" role="status"><p>{t('独立计量依据尚未确认，差额仅供参考，不作泄漏判断。')}</p></div>}
  <div className="energy-flow-metrics">
   <div className="energy-flow-metric"><span>{stats.overview?t('总表统计合计'):t('当前表计用量')}</span><strong>{valueText(stats.total)}<small>{unit}</small></strong><p>{stats.overview?t('不重复计入下级分表'):t('区间用量')}</p></div>
   <div className="energy-flow-metric"><span>{t('直属分表合计')}</span><strong>{valueText(stats.submeter)}<small>{unit}</small></strong><p>{share(stats.submeter)}</p></div>
   <div className={`energy-flow-metric${stats.difference!==null&&stats.difference<0?' energy-flow-metric-warning':''}`}><span>{focus.balanceMode==='consistency'?t('计算差额'):t('计量差额')}</span><strong>{valueText(stats.difference)}<small>{unit}</small></strong><p>{share(stats.difference)}</p></div>
   <div className="energy-flow-metric"><span>{stats.overview?t('总表数量'):t('直属分表数量')}</span><strong>{valueText(stats.count)}</strong><p>{stats.overview?t('{0} 块独立总表',valueText(stats.count)):t('计量关系自动生成')}</p></div>
  </div>
  <div className="energy-flow-toolbar"><nav className="energy-flow-path" aria-label={t('能流路径')}>{breadcrumbs.map((node,index)=><span key={node.id}>{index>0&&<span className="energy-flow-separator" aria-hidden="true">/</span>}{index===breadcrumbs.length-1?<b aria-current="page">{node.nodeType==='summary'?t('全项目概览'):nodeLabel(node)}</b>:<button type="button" disabled={exporting} onClick={()=>onFocus(node.nodeType==='summary'?'':node.id)}>{node.nodeType==='summary'?t('全项目概览'):nodeLabel(node)}</button>}</span>)}</nav><div className="energy-flow-legend">{legend.map(({node,color})=><span key={node.id}><i style={{background:color}}/>{nodeLabel(node)}</span>)}<span><i style={{background:'#a7b5bf'}}/>{t('计量差额')}</span></div></div>
  {anomalies.length>0&&<div className="energy-flow-notices" role="status">{anomalies.map(node=><p key={node.id}>{node.balanceQuality==='negativeBalance'?t('{0}：分表合计大于总表，差额为 {1} {2}，此分支不绘制流线。',nodeLabel(node),valueText(node.difference),t(node.unit)):t('{0}：缺测或计量关系不完整，此分支不绘制流线。',nodeLabel(node))}</p>)}</div>}
  <div className="energy-flow-graph-scroll" tabIndex={0} aria-label={t('能流图画布，可横向滚动')}>
   <svg className="energy-flow-graph" viewBox={`0 0 ${layout.width} ${layout.height}`} width={layout.width} height={layout.height} role="group" aria-labelledby={`${titleId} ${descriptionId}`}>
    <title id={titleId}>{t('能流图：{0}，合计 {1} {2}',nodeLabel(focus),valueText(stats.total),unit)}</title><desc id={descriptionId}>{t('图中包含 {0} 个节点和 {1} 条流线。详细读数见下方明细表。',layout.nodes.length,layout.links.length)}</desc>
    {[20,430,800].map((x,index)=><g key={x} aria-hidden="true"><text className="energy-flow-column-title" x={x} y={24}>{heading[index]}</text><line className="energy-flow-guide" x1={x+7} x2={x+7} y1={40} y2={layout.height-15}/></g>)}
    <g className="energy-flow-ribbons">{layout.links.map(({link,path,color})=>{const target=byId.get(link.target)!.node;return <Tooltip key={`${link.source}:${link.target}`} title={<FlowTooltip snapshot={snapshot} node={target} link={link}/>} color="#fff" open={exporting?false:undefined}><path d={path} fill={color} className="energy-flow-ribbon" data-flow-source={link.source} data-flow-target={link.target} data-flow-value={link.value} onClick={()=>{if(drillable(target)&&!exporting)onFocus(target.id);}}/></Tooltip>;})}</g>
    {layout.nodes.map(({node,depth,x,y,height,color})=>{const canDrill=drillable(node)&&node.id!==focus.id;const center=y+height/2;return <Tooltip key={node.id} title={<FlowTooltip snapshot={snapshot} node={node}/>} color="#fff" trigger={['hover','focus']} open={exporting?false:undefined}><g className={`energy-flow-node${canDrill?' energy-flow-node-action':''}`} role={canDrill?'button':'img'} tabIndex={exporting?-1:0} aria-label={t('{0}：{1} {2}',nodeLabel(node),valueText(node.value),t(node.unit))} aria-disabled={canDrill&&exporting?true:undefined} data-flow-node={node.id} data-flow-value={node.value??undefined} onClick={()=>{if(canDrill&&!exporting)onFocus(node.id);}} onKeyDown={event=>{if((event.key==='Enter'||event.key===' ')&&canDrill&&!exporting){event.preventDefault();onFocus(node.id);}}}>
     {height>0?<rect x={x} y={y} width={14} height={height} rx={2} fill={color}/>:<rect className="energy-flow-empty-marker" x={x+2} y={center-4} width={8} height={8} rx={1}/>}
     <rect className="energy-flow-hit" x={x-5} y={center-(depth===0?45:23)} width={depth===0?280:275} height={depth===0?90:46} fill="transparent"/>
     <text className={`energy-flow-node-name${node.nodeType==='difference'?' energy-flow-node-difference':''}`} x={x+27} y={center-(depth===0?24:4)}>{nodeLabel(node)}{canDrill?' ›':''}</text>
     <text className={depth===0?'energy-flow-root-value':'energy-flow-node-value'} x={x+27} y={center+(depth===0?7:14)}>{valueText(node.value)}{depth>0?` ${t(node.unit)}   ${shareText(node)}`:''}</text>
     {depth===0&&<text className="energy-flow-node-unit" x={x+28} y={center+28}>{t(node.unit)}</text>}
    </g></Tooltip>;})}
   </svg>
  </div>
  <div className="energy-flow-foot"><span className="energy-flow-desktop-hint">{t('流线粗细表示用量，点击表计查看下一级。')}</span><span className="energy-flow-mobile-hint">{t('手机可横向滑动查看完整流向。')}</span><span>{t('计量差额不直接等同于损耗')}</span></div>
  <section className="energy-flow-details ant-table-wrapper" aria-labelledby={detailsId}><div className="energy-flow-details-heading"><h3 id={detailsId}>{t('用量与计量明细')}</h3><span>{t('{0} 条明细',tableNodes.length)}</span></div><FlowDetails snapshot={snapshot} nodes={tableNodes} onFocus={onFocus} exporting={exporting}/><p className="energy-flow-table-foot">{t('统计合计仅计算独立总表，下级分表不重复相加。')}</p></section>
  {data.unassigned.length>0&&<section className="energy-flow-details energy-flow-unassigned ant-table-wrapper"><div className="energy-flow-details-heading"><h3>{t('未归属表计')}</h3><span>{t('{0} 条明细',data.unassigned.length)}</span></div><p className="energy-flow-unassigned-note">{t('{0} 块表计未能归入当前计量树，不参与统计合计。',data.unassigned.length)}</p><FlowDetails snapshot={snapshot} nodes={data.unassigned} onFocus={onFocus} exporting={exporting} unassigned/></section>}
 </section>;
}

export default EnergyFlowView;
