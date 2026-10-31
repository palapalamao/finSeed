import {useMemo,useState} from 'react';
import {Alert,Button,Empty,Select} from 'antd';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitBalanceSnapshot,cockpitCompactFlow} from './cockpitFlowProjection';
import {energyFlowGraphs,energyFlowGraphSnapshot,focusEnergyFlowSnapshot} from './energyFlow';
import {EnergyFlowGraphsView} from './EnergyFlowGraphsView';
import {cockpitReasonText} from './cockpitMetrics';
import {locale,t} from './i18n';
export function CockpitFlow({snapshot,focusObjectId,compact=false,onOpen}:{snapshot:CockpitSnapshot;focusObjectId?:string;compact?:boolean;onOpen:()=>void}){
 const report=useMemo(()=>cockpitBalanceSnapshot(snapshot),[snapshot,locale]);const graphs=useMemo(()=>report?energyFlowGraphs(report.result):[],[report]);
 const [chosen,setChosen]=useState<string>(),[localFocus,setLocalFocus]=useState<Record<string,string>>({}),[expanded,setExpanded]=useState(false);
 const selected=graphs.find(graph=>graph.graphId===chosen)||graphs.find(graph=>(graph.objectId||graph.focusId)===focusObjectId)||graphs[0],id=selected?.graphId||selected?.objectId||selected?.focusId;
 const panel=useMemo(()=>report&&id?focusEnergyFlowSnapshot(energyFlowGraphSnapshot(report,id),localFocus[id]):undefined,[report,id,localFocus]);
 const folded=panel?cockpitCompactFlow(panel):undefined;
 return <section className="cockpit-flow" aria-label={compact?t('能源去向'):t('计量平衡')}><h3>{compact?t('能源去向'):t('计量平衡')}</h3><p>{t('各对象独立展示，切换图和下钻仅使用当前快照；计量差额不等同于损耗。')}</p>
 {!!snapshot.modules.balance?.reasonCodes?.length&&<Alert type="info" showIcon message={snapshot.modules.balance.reasonCodes.map(cockpitReasonText).join(t('；'))}/>}
 {report&&panel&&id?<><label className="cockpit-flow-select">{t('选择能流对象')}<Select aria-label={t('选择能流对象')} value={id} onChange={value=>{setChosen(value);setExpanded(false);}} options={graphs.map(graph=>({value:graph.graphId||graph.objectId||graph.focusId,label:graph.nodes.find(node=>node.id===graph.focusId)?.name||graph.objectId||graph.focusId}))}/></label>
 <EnergyFlowGraphsView snapshot={report} panels={[compact&&!expanded?folded!.snapshot:panel]} exporting={false} onFocus={(graphId,next)=>setLocalFocus(previous=>({...previous,[graphId]:next}))}/>
 {compact&&folded!.hiddenCount>0&&<Button onClick={()=>setExpanded(value=>!value)}>{expanded?t('收起额外分支'):t('展开其余 {0} 个直属分支',folded!.hiddenCount)}</Button>}
 {compact&&<p>{t('精简视图只折叠分支，不合成其他用量；完整数值和共享关系仍保留。')}</p>}<Button onClick={onOpen}>{t('打开完整能流')}</Button></>:<Empty description={t('当前范围没有可用能流，请检查主点、上级表或表达式配置。')}/>}</section>;
}
