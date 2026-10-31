import {useMemo,useState} from 'react';
import {Alert,Button,Empty,Select} from 'antd';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitBalanceSnapshot} from './cockpitFlowProjection';
import {energyFlowGraphs,energyFlowGraphSnapshot,focusEnergyFlowSnapshot,energyFlowData,energyFlowNodeValue,energyFlowNodeQuality} from './energyFlow';
import {EnergyFlowGraphsView} from './EnergyFlowGraphsView';
import {cockpitMetricValue,cockpitReasonText} from './cockpitMetrics';
import {locale,t} from './i18n';
export function CockpitFlow({snapshot,focusObjectId,compact=false,onOpen}:{snapshot:CockpitSnapshot;focusObjectId?:string;compact?:boolean;onOpen:()=>void}){
 const report=useMemo(()=>cockpitBalanceSnapshot(snapshot),[snapshot,locale]);const graphs=useMemo(()=>report?energyFlowGraphs(report.result):[],[report]);
 const [chosen,setChosen]=useState<string>(),[localFocus,setLocalFocus]=useState<Record<string,string>>({}),[expanded,setExpanded]=useState(false);
 const selected=graphs.find(graph=>graph.graphId===chosen)||graphs.find(graph=>(graph.objectId||graph.focusId)===focusObjectId)||graphs[0],id=selected?.graphId||selected?.objectId||selected?.focusId;
 const panel=useMemo(()=>report&&id?focusEnergyFlowSnapshot(energyFlowGraphSnapshot(report,id),localFocus[id]):undefined,[report,id,localFocus]);
 const compactData=panel?energyFlowData(panel.result):undefined,root=compactData?.nodes.find(node=>node.id===compactData.focusId),branches=compactData?.nodes.filter(node=>node.parentId===root?.id&&!node.referenceOnly)||[];
 if(compact)return <section className="cockpit-flow cockpit-flow-compact" aria-label={t('能源去向')}><h3>{t('能源去向')}</h3><p>{t('只展示当前对象和直属去向，不将总表与子表重复相加。')}</p>{report&&root&&id?<>
  {graphs.length>1&&<label className="cockpit-flow-select">{t('选择能流对象')}<Select aria-label={t('选择能流对象')} value={id} onChange={value=>{setChosen(value);setExpanded(false);}} options={graphs.map(graph=>({value:graph.graphId||graph.objectId||graph.focusId,label:graph.nodes.find(node=>node.id===graph.focusId)?.name||graph.objectId||graph.focusId}))}/></label>}
  <div className="cockpit-destination-root"><strong>{root.name}</strong><span>{cockpitMetricValue({value:energyFlowNodeValue(root),valueType:root.knownValueType||'number'})} {root.unit}</span></div><p>{cockpitReasonText(energyFlowNodeQuality(root))}</p>
  <ul className="cockpit-destinations">{(expanded?branches:branches.slice(0,8)).map(node=><li key={node.id}><span>{node.name}</span><strong>{cockpitMetricValue({value:energyFlowNodeValue(node),valueType:node.knownValueType||'number'})} {node.unit}</strong><small>{cockpitReasonText(energyFlowNodeQuality(node))}</small></li>)}</ul>
  {branches.length===0&&<p>{t('当前对象没有已返回的直属去向。')}</p>}{branches.length>8&&<Button onClick={()=>setExpanded(value=>!value)}>{expanded?t('收起额外分支'):t('展开其余 {0} 个直属分支',branches.length-8)}</Button>}
  <p>{compactData?.additive===false||compactData?.sharedMemberIds?.length?t('存在共享或重叠来源，保留各对象用量，不计算互斥占比。'):t('精简视图只折叠分支，不合成其他用量；完整数值和共享关系仍保留。')}</p>
  </>:<Empty description={t('当前范围没有可用能流，请检查主点、上级表或表达式配置。')}/>}<Button onClick={onOpen}>{t('打开完整能流')}</Button></section>;
 return <section className="cockpit-flow" aria-label={t('计量平衡')}><h3>{compact?t('能源去向'):t('计量平衡')}</h3><p>{t('各对象独立展示，切换图和下钻仅使用当前快照；计量差额不等同于损耗。')}</p>
 {!!snapshot.modules.balance?.reasonCodes?.length&&<Alert type="info" showIcon message={snapshot.modules.balance.reasonCodes.map(cockpitReasonText).join(t('；'))}/>}
 {report&&panel&&id?<><label className="cockpit-flow-select">{t('选择能流对象')}<Select aria-label={t('选择能流对象')} value={id} onChange={value=>{setChosen(value);setExpanded(false);}} options={graphs.map(graph=>({value:graph.graphId||graph.objectId||graph.focusId,label:graph.nodes.find(node=>node.id===graph.focusId)?.name||graph.objectId||graph.focusId}))}/></label>
 <EnergyFlowGraphsView snapshot={report} panels={[panel]} exporting={false} onFocus={(graphId,next)=>setLocalFocus(previous=>({...previous,[graphId]:next}))}/>
  <Button onClick={onOpen}>{t('打开完整能流')}</Button></>:<Empty description={t('当前范围没有可用能流，请检查主点、上级表或表达式配置。')}/>}</section>;
}
