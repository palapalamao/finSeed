import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {expect,it} from 'vitest';
import edge from '../tests/fixtures/diagnostic-meta-edge-response.json';
import type {CockpitSnapshot,CockpitDiagnostics} from './cockpitTypes';
import type {ReportSnapshot} from './types';
import {diagnosticEntries,diagnosticRows,diagnosticGrain} from './cockpitDiagnostics';
import {DiagnosticNotice} from './DiagnosticNotice';
import {cockpitProfileSnapshot} from './cockpitReport';
import {projectCockpitReport} from './cockpitNavigation';
import {freezeCockpitExport,cockpitPrintEvidence} from './cockpitExports';
import {coverageGroups} from './knownUsageCoverage';
import {KnownUsageCoverage} from './KnownUsageCoverageView';
import {reportTables} from './exports';
import {reportCellText} from './reportDisplay';
import {ReportView} from './ReportView';
import {initializeLocale} from './i18n';
const actual=()=>JSON.parse(gunzipSync(readFileSync(new URL('../tests/fixtures/cockpit-diagnostics-response.json.gz',import.meta.url))).toString()) as CockpitSnapshot;
const metadata=edge.diagnostics as CockpitDiagnostics;
it('keeps global1000budget separate from full numerical reports, metrics and heatmap',()=>{
 const snapshot=actual(),before=structuredClone(snapshot),report=cockpitProfileSnapshot(snapshot)!;const projected=projectCockpitReport(snapshot,report.request)!;
 expect(projected.diagnostics).toMatchObject({snapshotId:snapshot.snapshotId,reportRefs:[snapshot.modules.trend!.data!.reportRef],metadata:{rowBudget:1000,returnedCount:1000,truncated:true}});
 expect(snapshot.modules.time!.data!.heatmap).toHaveLength(8760);expect(projected.result.series).toEqual(report.result.series);expect(snapshot).toEqual(before);expect(diagnosticEntries(metadata,['unknown-report'])).toEqual([]);
});
it('explains zero returned records, unknown totals and distinct sourceRead grain in both languages',()=>{
 for(const language of ['zh-CN','en-US']){initializeLocale(language);const html=renderToStaticMarkup(createElement(DiagnosticNotice,{metadata,reportRefs:['flow'],snapshotId:'parent'}));expect(html).toContain(language==='zh-CN'?'未知':'Unknown');expect(html).toContain(language==='zh-CN'?'不能据此判断没有缺口':'does not mean there are no gaps');expect(html).toContain(language==='zh-CN'?'源读取时段':'Source read period');expect(html).toContain(language==='zh-CN'?'不能用条数计算覆盖时长':'must not be converted into coverage duration');expect(diagnosticGrain('hour')).not.toContain('总小时数');}
 const unknown=diagnosticRows(metadata).find(row=>row[0]==='diagnostic-5')!;expect(unknown[3]).toBe(0);expect(unknown[4]).toBe('Unknown');expect(unknown[12]).toBe('Not included');
});
it('limited sourceUsage cannot masquerade as complete covered time or absence of gaps',()=>{
 const snapshot:ReportSnapshot={project:'test',title:'diagnostics',generatedAt:edge.context.asOf,request:{kind:'profile',nodeIds:['site'],from:edge.context.time.from,to:edge.context.time.to,asOf:edge.context.asOf,period:'month',metric:'energy',perArea:false},result:structuredClone(edge.reports.flow) as unknown as ReportSnapshot['result'],diagnostics:{snapshotId:'parent',reportRefs:['flow'],metadata}};
 const before=structuredClone(snapshot),groups=coverageGroups(snapshot);expect(groups.length).toBeGreaterThan(0);expect(groups[0]).toMatchObject({diagnosticLimited:true,coveredSeconds:null,intervalCount:null,diagnosticReturnedCount:250,diagnosticTotalCount:5000});expect(snapshot).toEqual(before);
 initializeLocale('en-US');const html=renderToStaticMarkup(createElement(KnownUsageCoverage,{snapshot}));expect(html).toContain('returned fragments');expect(html).not.toContain('No missing or abnormal periods.');
});
it('interval-only limits preserve authoritative source-read coverage and declare omitted intervals',()=>{
 const raw=actual(),base=cockpitProfileSnapshot(raw)!,usage=base.result.extra!.knownUsage as any;const row=usage.sourceUsage[0];expect(row).toBeTruthy();usage.sourceUsage=[{...row,detailsTruncated:false,intervals:[],intervalsDiagnosticRef:'interval-only'}];usage.sourceUsageTruncated=false;delete usage.sourceUsageDiagnosticRef;
 const entry={...metadata.entries.find(entry=>entry.kind==='sourceIntervals')!,id:'interval-only'};base.diagnostics={snapshotId:'p',reportRefs:['profile-energy'],metadata:{...metadata,entries:[entry]}};const group=coverageGroups(base)[0];expect(group.diagnosticLimited).toBe(false);expect(group.coveredSeconds).toBe(row.coveredSeconds);expect(group.detailsTruncated).toBe(true);expect(base.result.summary).toEqual(cockpitProfileSnapshot(raw)!.result.summary);
});
it('exports retain complete returned metadata and sharedDAG while print references counts without inventing unknown totals',()=>{
 const snapshot=actual();snapshot.diagnostics=metadata;const shared={test:[1,2,3]};snapshot.reports['profile-energy'].extra={...snapshot.reports['profile-energy'].extra,shared};snapshot.reports['profile-cost'].extra={...snapshot.reports['profile-cost'].extra,shared};const packet=freezeCockpitExport(snapshot,'en-US',{});
 expect(packet.diagnosticNotice).toContain('partially returned');expect(packet.snapshot.diagnostics).toEqual(metadata);expect(packet.snapshot.reports['profile-energy'].extra!.shared).toBe(packet.snapshot.reports['profile-cost'].extra!.shared);expect(Object.isFrozen(packet.snapshot.reports['profile-energy'].extra!.shared)).toBe(true);
 const printed=cockpitPrintEvidence(packet);expect(printed.diagnostics).toMatchObject({rowBudget:1000,returnedCount:1000,truncated:true,entriesRef:'diagnostic-return-scope'});expect(packet.snapshot.modules.kpis!.data!.values.find(metric=>metric.id==='energy')!.value).toBe(snapshot.modules.kpis!.data!.values.find(metric=>metric.id==='energy')!.value);
});

it('opaque capture identities stay in evidence but not business columns; sidecar counts and limits are localized without altering usage',()=>{
 const row={name:'Meter',value:0,unit:'kWh',periodsCaptureId:'OPAQUE_CAPTURE_SENTINEL',sourceUsageCaptureId:'OPAQUE_READ_SENTINEL',detailsCaptureId:'OPAQUE_CLEAN_SENTINEL',intervalsCaptureId:'OPAQUE_INTERVAL_SENTINEL',periodRecordTotalCount:8760,periodsReturnedCount:2,periodsTruncated:true,periodsTruncationReason:'cockpitPeriodCaptureLimit'};
 const report:ReportSnapshot={project:'test',title:'Capture fields',generatedAt:'2026-11-01T00:00:00Z',request:{kind:'profile',nodeIds:['m'],from:'2026-10-01T00:00:00Z',to:'2026-10-02T00:00:00Z',period:'hour',metric:'energy',perArea:false},result:{kind:'profile',from:'2026-10-01T00:00:00Z',to:'2026-10-02T00:00:00Z',period:'hour',rows:[row],series:[],summary:{},extra:{},warnings:[]}};
 const before=structuredClone(report);
 for(const language of ['zh-CN','en-US']){initializeLocale(language);const html=renderToStaticMarkup(createElement(ReportView,{snapshot:report}));expect(html).not.toContain('OPAQUE_');expect(reportTables(report).headers.join('|')).not.toContain('CaptureId');expect(html).toContain(language==='zh-CN'?'已返回覆盖时段诊断数':'Returned coverage-period diagnostic records');expect(reportCellText(report,'periodsTruncated',true)).toBe(language==='zh-CN'?'是':'Yes');expect(reportCellText(report,'periodsTruncationReason','cockpitPeriodCaptureLimit')).toContain(language==='zh-CN'?'覆盖时段诊断记录上限':'Coverage-period diagnostic record limit');}
 const meta={...metadata,entries:[{...metadata.entries[0],upstreamReason:'cockpitPeriodCaptureLimit'}]};expect(renderToStaticMarkup(createElement(DiagnosticNotice,{metadata:meta}))).toContain('Coverage-period diagnostic record limit reached');expect(report).toEqual(before);expect(report.result.rows[0].value).toBe(0);expect(JSON.stringify(report)).toContain('OPAQUE_CAPTURE_SENTINEL');
});
