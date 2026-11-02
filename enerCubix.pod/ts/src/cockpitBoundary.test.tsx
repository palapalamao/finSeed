import {expect,it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import raw from '../tests/fixtures/cockpit-space-response.json';
import {CockpitFlow} from './CockpitFlow';
import type {CockpitSnapshot} from './cockpitTypes';
import type {EnergyFlowData,EnergyFlowNode} from './energyFlow';
import {cockpitReasonText} from './cockpitMetrics';
import {t} from './i18n';

function renderBoundary(quality:string,difference:number|null,basis:EnergyFlowData['basis']='metering'){
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 const total=difference===0?100:90;
 const root:EnergyFlowNode={id:'t',name:'Independent total',nodeType:'meter',categoryId:'c',unit:'kWh',value:total,quality:'ok',sourceIds:['pt'],submeter:100,difference,balanceQuality:quality,balanceMode:'independent',lossEligible:false,hasChildren:true,percentage:null,knownValue:total,knownValueType:'number',knownQuality:'ok',coverage:1};
 const child=(id:string,value:number):EnergyFlowNode=>({...root,id,name:id,parentId:'t',sourceIds:['p'+id],value,knownValue:value,submeter:null,difference:null,balanceQuality:'ok',hasChildren:false});
 const graph:EnergyFlowData={graphId:'boundary',objectId:'t',basis,categoryId:'c',unit:'kWh',focusId:'t',rootIds:['t'],nodes:[root,child('a',40),child('b',60)],links:[],unassigned:[],sharedMemberIds:quality==='overlappingScopes'?['a']:[],additive:quality!=='overlappingScopes'};
 const ref=snapshot.modules.balance!.data!.reportRef;
 snapshot.reports[ref].extra={...snapshot.reports[ref].extra,energyFlowGraphs:[graph],energyFlow:graph};
 const before=structuredClone(snapshot),html=renderToStaticMarkup(<CockpitFlow snapshot={snapshot} compact onOpen={()=>{}}/>);
 expect(snapshot).toEqual(before);return html;
}
it('retains the independently known 90 minus 40 minus 60 difference even when loss is ineligible',()=>{
 const html=renderBoundary('negativeBalance',-10);
 expect(html).toContain('<dd>-10 kWh');expect(html).toContain(cockpitReasonText('negativeBalance'));
});
it('preserves a real zero complete difference',()=>{expect(renderBoundary('ok',0)).toContain('<dd>0 kWh</dd>');});
it('does not turn incomplete or overlapping evidence into a reliable difference',()=>{
 for(const quality of ['missing','overlappingScopes']){const html=renderBoundary(quality,null);expect(html).toContain(t('无法判断'));expect(html).not.toContain('-10 kWh');}
});
it('does not treat a shared scope distribution as a physical total/submeter check',()=>{
 const html=renderBoundary('ok',-10,'space');expect(html).toContain(t('无法判断'));expect(html).not.toContain('-10 kWh');
});
