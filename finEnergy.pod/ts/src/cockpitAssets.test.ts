import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {expect,it,vi} from 'vitest';
vi.mock('haystack-nclient',()=>({finCsrfFetch:vi.fn()}));
import actual from '../tests/fixtures/cockpit-space-response.json';
import type {CockpitSnapshot} from './cockpitTypes';
import type {Catalog} from './types';
import {hotspotNode,type CockpitAssetEvidence} from './cockpitAssets';
import {FinEnergyApi} from './api';
import {cockpitSpaceAssociations} from './cockpitSpaceProjection';
import {CockpitSpace} from './CockpitSpace';
import {freezeCockpitExport} from './cockpitExports';
import {CockpitReportDocument} from './CockpitPresentation';
import {initializeLocale} from './i18n';
const snapshot=()=>structuredClone(actual) as unknown as CockpitSnapshot;
const catalog:Catalog={project:'test',version:'0',spaceSource:'fin',user:{name:'su',canWrite:true},records:[{id:'s',kind:'space',name:'Site',nativeSourceKind:'site'},{id:'f',kind:'space',name:'Floor',nativeSourceKind:'floor',parentId:'s'},{id:'a',kind:'meter',name:'设备 A',pointId:'pa',nativeTreeParentId:'f'},{id:'pa',kind:'nativePoint',name:'主点 A'}]};
it('maps native Ref hotspots to current overlay IDs without changing the statistical packet',()=>{
 const raw=snapshot(),before=structuredClone(raw),floor=raw.modules.space!.data!.nodes.find(n=>n.id==='f')!;floor.id='legacy-floor';floor.nativeId='p:test:r:floor';
 expect(hotspotNode(raw.modules.space!.data!.nodes,'p:test:r:floor')?.id).toBe('legacy-floor');expect(hotspotNode(raw.modules.space!.data!.nodes,'unmapped')).toBeUndefined();expect(raw.modules.kpis).toEqual(before.modules.kpis);expect(raw.reports).toEqual(before.reports);
});
it('P11 shows only confirmed same-packet equipment/primary-point/source-item associations, with unknown IDs withheld',()=>{
 const raw=snapshot(),focus=raw.modules.space!.data!.nodes.find(node=>node.id==='f')!;focus.meterIds=['a','HIDDEN_REF_SENTINEL'];const before=structuredClone(raw),result=cockpitSpaceAssociations(raw,catalog,focus);expect(result.items.map(row=>row.node.id)).toEqual(['a']);expect(result.items[0].points).toEqual([{id:'pa',name:'主点 A'}]);expect(result.unresolved).toBe(true);
 for(const language of ['zh-CN','en-US']){initializeLocale(language);const html=renderToStaticMarkup(createElement(CockpitSpace,{snapshot:raw,catalog,focusObjectId:'f',onFocus:()=>{},onPromote:()=>{},onProfile:()=>{},onFlow:()=>{}}));expect(html).toContain('主点 A');expect(html).not.toContain('HIDDEN_REF_SENTINEL');expect(html).toContain(language==='zh-CN'?'自身用量与质量':'Own usage and quality');}
 expect(raw).toEqual(before);
});
it('freezes display metadata separately from numeric snapshot, and explicitly discloses uncaptured image pixels',()=>{
 const raw=snapshot(),display:CockpitAssetEvidence={asset:{id:'asset',mod:'v1',hash:'a'.repeat(64),name:'客户图纸.png',scopeId:'s',mime:'image/png',width:1200,height:600,size:100,updatedBy:'su',updatedAt:'2026-11-01T00:00:00Z',hotspots:[{spaceId:'f',x:0.25,y:0.5}]},displayed:true,observedAt:'2026-11-01T01:00:00Z',imageCaptured:false};
 for(const language of ['zh-CN','en-US'] as const){initializeLocale(language);const packet=freezeCockpitExport(raw,language,{},display);display.asset.mod='v2';display.asset.hotspots[0].x=0.75;expect(packet.assetEvidence!.asset.mod).not.toBe(display.asset.mod);expect(packet.assetEvidence!.asset.hotspots[0].x).not.toBe(display.asset.hotspots[0].x);expect(packet.snapshot).toEqual(raw);expect(Object.isFrozen(packet.assetEvidence!.asset.hotspots)).toBe(true);const html=renderToStaticMarkup(createElement(CockpitReportDocument,{packet}));expect(html).toContain(language==='zh-CN'?'未捕获附件像素':'Attachment pixels were not captured');display.asset.mod='v1';display.asset.hotspots[0].x=0.25;}
});
it('image URLs remain the authenticated same-origin project endpoint even for hostile identifier strings',()=>{
 const api=new FinEnergyApi('test');const url=api.assetImageUrl({id:'https://example.invalid/../../secret',hash:'a&other=x'});expect(new URL(url,'http://localhost:8080').origin).toBe('http://localhost:8080');expect(url).toContain('/api/test/ext/finEnergy/v1/cockpit/assets/image?');expect(new URL(url,'http://localhost').searchParams.get('id')).toBe('https://example.invalid/../../secret');expect(new URL(url,'http://localhost').searchParams.has('other')).toBe(false);
});
