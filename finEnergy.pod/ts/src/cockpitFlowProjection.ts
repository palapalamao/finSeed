import type {CockpitSnapshot} from './cockpitTypes';
import type {ReportSnapshot} from './types';
import {energyFlowData,energyFlowGraphs,energyFlowGraphSnapshot,focusEnergyFlowSnapshot} from './energyFlow';
import {t} from './i18n';
export function cockpitBalanceSnapshot(snapshot:CockpitSnapshot,nodeIds=snapshot.context.reportScope.nodeIds):ReportSnapshot|undefined{
 const ref=snapshot.modules.balance?.data?.reportRef,raw=ref?snapshot.reports[ref]:undefined;if(!raw)return;
 const c=snapshot.context,report:ReportSnapshot={project:c.project,title:t('计量平衡'),generatedAt:snapshot.generatedAt,request:{kind:'energyFlow',nodeIds:[...c.reportScope.nodeIds],dimension:c.reportScope.dimension,...(c.reportScope.dimension==='space'?{spaceSource:'fin' as const}:{}),categoryId:c.focusCategoryId,from:c.time.from,to:c.time.to,asOf:c.asOf,period:c.time.period,metric:'energy',perArea:false,flowMode:'relations'},result:structuredClone(raw)};
 if(JSON.stringify(nodeIds)===JSON.stringify(c.reportScope.nodeIds))return report;
 if(nodeIds.length!==1)return;const graphs=energyFlowGraphs(report.result),graph=graphs.find(g=>nodeIds[0]===(g.objectId||g.focusId))||graphs.find(g=>g.nodes.some(n=>!n.referenceOnly&&n.nodeType!=='difference'&&(n.nodeId||n.id)===nodeIds[0]));if(!graph)return;
 const root=energyFlowGraphSnapshot(report,graph.graphId||graph.objectId||graph.focusId),child=graph.nodes.find(n=>!n.referenceOnly&&n.nodeType!=='difference'&&(n.nodeId||n.id)===nodeIds[0]);
 const one=child&&nodeIds[0]!==(graph.objectId||graph.focusId)?focusEnergyFlowSnapshot(root,child.id):root;one.result.extra={...one.result.extra,energyFlowGraphs:[energyFlowData(one.result)!]};return one;
}
// View-only pruning: never combine hidden branches or recalculate any energy.
export function cockpitCompactFlow(snapshot:ReportSnapshot):{snapshot:ReportSnapshot;hiddenCount:number}{
 const data=energyFlowData(snapshot.result);if(!data)return {snapshot,hiddenCount:0};
 const focus=data.nodes.find(node=>node.id===data.focusId);if(!focus)return {snapshot,hiddenCount:0};
 const children=data.nodes.filter(node=>node.parentId===focus.id&&node.nodeType!=='difference'&&!node.referenceOnly),visible=new Set([focus.id,...children.slice(0,8).map(node=>node.id),...data.nodes.filter(node=>node.parentId===focus.id&&(node.nodeType==='difference'||node.referenceOnly)).map(node=>node.id)]);
 const graph={...data,nodes:data.nodes.filter(node=>visible.has(node.id)),links:data.links.filter(link=>visible.has(link.source)&&visible.has(link.target)),unassigned:[]};
 return {snapshot:{...snapshot,result:{...snapshot.result,extra:{...snapshot.result.extra,energyFlow:graph}}},hiddenCount:Math.max(0,children.length-8)};
}
