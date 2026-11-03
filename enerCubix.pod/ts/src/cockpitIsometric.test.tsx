import {expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import raw from '../tests/fixtures/cockpit-space-response.json';
import type {CockpitSpaceNode} from './cockpitTypes';
import {cockpitSpaceSites} from './cockpitSpaceProjection';
import {CockpitIsometricSpace} from './CockpitIsometricSpace';
import {CockpitFlow} from './CockpitFlow';
import {chartOptions,compactChartOptions} from './chartOptions';
import {cockpitProfileSnapshot} from './cockpitReport';

it('draws exactly the real sites and floors without inventing buildings or own energy',()=>{
 const nodes=structuredClone(raw).modules.space.data.nodes as unknown as CockpitSpaceNode[];
 const sites=cockpitSpaceSites(nodes),before=structuredClone(nodes),html=renderToStaticMarkup(<CockpitIsometricSpace sites={sites} onFocus={()=>{}} path={id=>id}/>);
 expect(sites).toHaveLength(1);expect(html.match(/data-native-site=/g)).toHaveLength(1);expect(html.match(/class="cockpit-building-floor"/g)).toHaveLength(1);expect(html).toContain('data-space-object="s"');expect(html).toContain('data-space-object="f"');expect(html).toContain('tabindex="0"');expect(html).toContain('30 kWh');expect(nodes).toEqual(before);
});
it('keeps a real site without floors and preserves NA and zero instead of a child sum',()=>{
 const site=structuredClone(raw).modules.space.data.nodes.find(node=>node.nodeKind==='site')!;
 for(const [value,valueType,expected] of [[null,'na','NA'],[0,'number','0']] as const){const sites=cockpitSpaceSites([{...site,value,valueType}] as unknown as Parameters<typeof cockpitSpaceSites>[0]);const html=renderToStaticMarkup(<CockpitIsometricSpace sites={sites} onFocus={()=>{}} path={id=>id}/>);expect(sites).toHaveLength(1);expect(html).not.toContain('cockpit-building-floor');expect(html).toContain(expected+' kWh');}
 expect(cockpitSpaceSites([])).toEqual([]);
});
it('states that a scope graph does not prove parent/submeter coverage or a complete difference',()=>{
 const snapshot=structuredClone(raw) as unknown as Parameters<typeof CockpitFlow>[0]['snapshot'],before=structuredClone(snapshot);
 const html=renderToStaticMarkup(<CockpitFlow snapshot={snapshot} compact onOpen={()=>{}}/>);
 expect(html).toContain('cockpit-boundary-status');expect(html).toContain('30');expect(html).not.toContain('energy-flow-graph-scroll');expect(html).not.toContain('<table');expect(snapshot).toEqual(before);
});

it('gives the overview usable plotting space without changing points, axes or the professional chart',()=>{const snapshot=structuredClone(raw) as unknown as Parameters<typeof cockpitProfileSnapshot>[0],report=cockpitProfileSnapshot(snapshot)!,options=chartOptions(report.result,{}, {type:'line',request:report.request}),before={...options},compact=compactChartOptions(options);expect(compact.series).toBe(options.series);expect(compact.xAxis).toBe(options.xAxis);expect(compact.dataZoom).toEqual([]);expect(compact.grid).toMatchObject({top:28,bottom:30});expect(compact.legend).toMatchObject({show:false});expect((compact.yAxis as any[])[0]).toMatchObject({splitNumber:3,axisLabel:{hideOverlap:true}});expect(options).toEqual(before);});

it('leaves a readable plot beside long organization labels in a narrow cockpit without changing the report',()=>{
 const label='Unassigned organization / a very long native business name (kWh)',options={grid:{left:140,right:35},xAxis:{type:'value'},yAxis:{type:'category',data:[label]},series:[{type:'bar',data:[180]}]},before=structuredClone(options),compact=compactChartOptions(options),grid=compact.grid as {left:number;right:number};
 expect(244-grid.left-grid.right).toBeGreaterThanOrEqual(130);expect(compact.xAxis).toMatchObject({splitNumber:3,axisLabel:{hideOverlap:true}});expect(compact.yAxis).toMatchObject({data:[label],axisLabel:{overflow:'truncate'}});expect(compact.series).toBe(options.series);expect(options).toEqual(before);
});
