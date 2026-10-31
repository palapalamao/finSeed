import {expect,it} from 'vitest';
import type {CockpitSnapshot} from './cockpitTypes';
import raw from '../tests/fixtures/cockpit-faces-response.json';
import {initializeLocale,serverMessage} from './i18n';
import {cockpitReferencedReport,cockpitOrganizationReport} from './cockpitReport';
import {createFaceNavigation,decodeNavigation,encodeNavigation,projectCockpitReport} from './cockpitNavigation';
it('projects three faces from the same immutable serialized snapshot and preserves energy units',()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot,before=structuredClone(snapshot);
 const daily=cockpitReferencedReport(snapshot,snapshot.modules.time!.data!.dailyReportRef)!;
 expect(daily.result.series.map(series=>series.unit)).toEqual(['kWh','kWh']);expect(daily.result.series[0].points[0].value).toBe(5);
 expect(snapshot.modules.time!.data!.heatmap).toHaveLength(48);
 const uses=cockpitReferencedReport(snapshot,snapshot.modules.endUse!.data!.reportRef)!;
 expect((uses.result.extra!.utilityShares as {knownPercentage:number}[]).map(row=>row.knownPercentage)).toEqual([40,60]);
 const organization=cockpitOrganizationReport(snapshot)!;
 expect(organization.result.rows.map(row=>row.value).sort((a,b)=>Number(a)-Number(b))).toEqual([120,180]);
 expect(organization.result.rows.find(row=>row.nodeKind==='unassigned')?.name).toBeTruthy();expect(snapshot).toEqual(before);
});
it('keeps face and parent comparison while drilling to the exact prepared meter boundary',()=>{
 const snapshot=structuredClone(raw) as unknown as CockpitSnapshot;
 const view={selectedFace:'time' as const,presentationMode:false,scrollY:123,draft:{scope:snapshot.context.reportScope,categoryId:'c',preset:'custom' as const}};
 const navigation=createFaceNavigation(snapshot,'daily',view);
 expect(navigation.targetRequest).toMatchObject({kind:'daily',dimension:'metering',nodeIds:['a','b'],period:'hour',from:snapshot.context.time.from,to:snapshot.context.time.to,asOf:snapshot.context.asOf});
 expect(decodeNavigation(encodeNavigation(navigation),'test')?.selectedFace).toBe('time');
 expect(projectCockpitReport(snapshot,navigation.targetRequest)?.result.series[0].points[0].value).toBe(5);
 expect(projectCockpitReport(snapshot,{...navigation.targetRequest,metric:'cost'})).toBeUndefined();
});
it.each(['zh-CN','en-US'])('explains shared-query resource errors in %s',language=>{
 initializeLocale(language);
 for(const code of ['cockpitBusy','cockpitQueryTimeout','cockpitHistoryDensityLimit','cockpitHistoryScanLimit','cockpitHistoryMemoryLimit','cockpitPreparedReadLimit','cockpitResponseLimit']){
  const text=serverMessage(code);expect(text).not.toBe(code);expect(/\p{Script=Han}/u.test(text)).toBe(language==='zh-CN');
 }
 initializeLocale('zh-CN');
});
