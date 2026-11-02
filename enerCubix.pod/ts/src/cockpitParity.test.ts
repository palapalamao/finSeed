import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {expect,it} from 'vitest';
import actual from '../tests/fixtures/cockpit-space-response.json';
import balance from '../tests/fixtures/cockpit-balance-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import {cockpitModules} from './cockpitTypes';
import type {Catalog} from './types';
import {cockpitSpaceObjects,cockpitSpaceSites} from './cockpitSpaceProjection';
import {CockpitSpace} from './CockpitSpace';
import {CockpitFlow} from './CockpitFlow';
import {CockpitKpis} from './CockpitKpis';
import {initializeLocale} from './i18n';
const catalog:Catalog={project:'test',version:'test',spaceSource:'fin',user:{name:'reader',canWrite:false},records:[{id:'s',kind:'space',name:'Site',nativeReadonly:true,nativeSourceKind:'site'},{id:'f',kind:'space',name:'Floor',parentId:'s',nativeReadonly:true,nativeSourceKind:'floor'},...['a','b'].map(id=>({id,kind:'meter' as const,name:id==='a'?'Meter A':'Meter B',nativeEquip:true,nativeTreeParentId:'f',pointId:'p'+id,categoryId:'c'})),...['pa','pb'].map(id=>({id,kind:'nativePoint' as const,name:'Readable '+id,nativeSourceId:id,his:true}))]};
it('projects real serialized site/floor and own-primary numbers without changing the snapshot',()=>{
 const snapshot=structuredClone(actual) as unknown as CockpitSnapshot,before=structuredClone(snapshot),objects=cockpitSpaceObjects(snapshot,catalog);
 expect(cockpitModules).toContain('space');expect(cockpitModules).toHaveLength(9);expect(cockpitSpaceSites(objects).map(group=>[group.site.id,group.floors.map(floor=>floor.id)])).toEqual([['s',['f']]]);
 expect(objects.find(node=>node.id==='f')).toMatchObject({basis:'scopeAggregate',value:30,sourceIds:['pa','pb']});expect(objects.find(node=>node.id==='a')).toMatchObject({basis:'ownPrimary',value:10,sourceIds:['pa']});expect(snapshot).toEqual(before);
});
it('keeps legacy or not-loaded own values missing even with valid child history',()=>{
 const snapshot=structuredClone(actual) as unknown as CockpitSnapshot;delete snapshot.modules.space;
 expect(cockpitSpaceObjects(snapshot,catalog).every(node=>node.value===null&&node.reasonCodes.includes('notLoaded'))).toBe(true);
 expect(snapshot.modules.kpis!.data!.values.find(metric=>metric.id==='energy')!.value).toBe(30);
 const objects=cockpitSpaceObjects(snapshot,{...catalog,records:catalog.records.filter(row=>row.id!=='f')});expect(cockpitSpaceSites(objects).map(group=>[group.site.id,group.floors])).toEqual([['s',[]]]);
});
it('renders same-object NA, zero and missing distinctly with source evidence in both languages',()=>{
 for(const language of ['zh-CN','en-US']){initializeLocale(language);const snapshot=structuredClone(actual) as unknown as CockpitSnapshot,node=snapshot.modules.space!.data!.nodes.find(node=>node.id==='a')!;
 const render=()=>renderToStaticMarkup(createElement(CockpitSpace,{snapshot,catalog,focusObjectId:'a',onFocus:()=>{},onPromote:()=>{},onProfile:()=>{},onFlow:()=>{}}));
 node.value=null;node.valueType='na';node.completeValue=null;expect(render()).toContain('NA');expect(render()).toContain('Readable pa');
 node.value=0;node.valueType='number';node.completeValue=0;expect(render()).toContain('>0 <small>kWh</small>');
 node.value=null;node.valueType='null';node.reasonCodes=['FOCUS_NOT_LOADED'];node.quality='notLoaded';const missing=render();expect(missing).toContain('—');expect(missing).toContain(language==='zh-CN'?'不以子表合计代替':'A child-meter sum is not substituted');
 }
});
it('renders a true compact destination list without full SVG or source tables',()=>{
 initializeLocale('en-US');const snapshot=structuredClone(balance) as unknown as CockpitSnapshot,before=structuredClone(snapshot);const html=renderToStaticMarkup(createElement(CockpitFlow,{snapshot,compact:true,onOpen:()=>{}}));expect(html).toContain('cockpit-destinations');expect(html).not.toContain('energy-flow-graph-scroll');expect(html).not.toContain('<table');expect(snapshot).toEqual(before);
});
it('explains a local KPI internal error while retaining other valid numbers',()=>{
 const snapshot=structuredClone(actual) as unknown as CockpitSnapshot,metric=snapshot.modules.kpis!.data!.values.find(metric=>metric.id==='cost')!;metric.value=null;metric.valueType='null';metric.reasonCodes=['COCKPIT_METRIC_ERROR'];metric.quality='metricError';
 for(const language of ['zh-CN','en-US']){initializeLocale(language);const html=renderToStaticMarkup(createElement(CockpitKpis,{snapshot,name:id=>id}));expect(html).toContain(language==='zh-CN'?'此指标计算失败':'This metric could not be calculated');expect(html).toContain('>30 <small>kWh</small>');}
});
