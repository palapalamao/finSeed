import {expect,it} from 'vitest';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {CockpitFlow} from './CockpitFlow';
import {initializeLocale} from './i18n';
import raw from '../tests/fixtures/cockpit-balance-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitBalanceSnapshot,cockpitCompactFlow} from './cockpitFlowProjection';
import {energyFlowGraphs,energyFlowGraphSnapshot,energyFlowData} from './energyFlow';
import {createNavigation,decodeNavigation,encodeNavigation,projectCockpitReport} from './cockpitNavigation';
for(const language of ['zh-CN','en-US'] as const)it('focuses a returned child graph without changing the reporting scope '+language,()=>{
 initializeLocale(language);const source=structuredClone(raw) as unknown as CockpitSnapshot,before=structuredClone(source);
 const graph=energyFlowGraphs(cockpitBalanceSnapshot(source)!.result).find(g=>g.objectId==='t')!,child=graph.nodes.find(n=>n.nodeType==='meter'&&n.parentId===graph.focusId&&!n.referenceOnly)!;
 const html=renderToStaticMarkup(createElement(CockpitFlow,{snapshot:source,focusObjectId:child.nodeId||child.id,compact:true,onOpen:()=>{}}));
 expect(html.match(/class="cockpit-destination-root"[\s\S]*?<\/strong>/)?.[0]).toContain('>'+child.name+'</strong>');expect(source).toEqual(before);
 const navigation=createNavigation(source,'energyFlow',{focusObjectId:child.nodeId||child.id,selectedFace:'space',presentationMode:false,scrollY:0,draft:{scope:source.context.reportScope,categoryId:source.context.focusCategoryId,preset:'custom'}}),projected=projectCockpitReport(source,navigation.targetRequest);
 expect(projected).toBeDefined();const focused=energyFlowData(projected!.result)!;expect(focused.focusId).toBe(child.id);expect(focused.nodes.find(n=>n.id===focused.focusId)).toMatchObject({value:child.value,sourceIds:child.sourceIds});expect(projected!.request.nodeIds).toEqual([child.nodeId||child.id]);expect(source).toEqual(before);
 const fallback=renderToStaticMarkup(createElement(CockpitFlow,{snapshot:source,focusObjectId:'unloaded-focus',compact:true,onOpen:()=>{}}));
 expect(fallback).toContain(language==='zh-CN'?'当前焦点没有已返回的能流':'No energy flow was returned for the current focus');expect(source).toEqual(before);
});
it('projects independent graphs and preserves an unavailable mixed accounting total',()=>{
 const source=structuredClone(raw) as unknown as CockpitSnapshot,before=structuredClone(source),report=cockpitBalanceSnapshot(source)!;
 expect(energyFlowGraphs(report.result)).toHaveLength(3);expect(report.result.extra!.energyFlowAccounting).toMatchObject({unionValue:null});
 expect(source).toEqual(before);
 const view={selectedFace:'balance' as const,presentationMode:false,scrollY:77,focusObjectId:'t',draft:{scope:source.context.reportScope,categoryId:source.context.focusCategoryId,preset:'custom' as const}};
 const navigation=createNavigation(source,'energyFlow',view);delete navigation.targetRequest.otherFrom;delete navigation.targetRequest.otherTo;
 expect(decodeNavigation(encodeNavigation(navigation),'test')?.selectedFace).toBe('balance');
 const projected=projectCockpitReport(source,navigation.targetRequest)!;expect(energyFlowGraphs(projected.result)).toHaveLength(1);expect(projected.result.extra!.energyFlowAccounting).toBeUndefined();expect(source).toEqual(before);
});
it('folds after eight direct branches without inventing an other subtotal or mutating values',()=>{
 const report=energyFlowGraphSnapshot(cockpitBalanceSnapshot(structuredClone(raw) as unknown as CockpitSnapshot)!,'metering|t'),data=energyFlowData(report.result)!,root=data.nodes.find(node=>node.id===data.focusId)!;
 const child=data.nodes.find(node=>node.parentId===root.id&&node.nodeType!=='difference')!;
 data.nodes=[root,...Array.from({length:11},(_,index)=>({...child,id:'branch'+index,nodeId:'m'+index,parentId:root.id}))];data.links=[];
 const before=structuredClone(report),compact=cockpitCompactFlow(report);expect(compact.hiddenCount).toBe(3);expect(energyFlowData(compact.snapshot.result)!.nodes).toHaveLength(9);expect(energyFlowData(compact.snapshot.result)!.nodes[0].value).toBe(root.value);expect(report).toEqual(before);
});
