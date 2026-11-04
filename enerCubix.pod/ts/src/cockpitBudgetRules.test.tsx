import {qualityLabel} from './reportQuality';
import {cockpitReasonText} from './cockpitMetrics';
import {it,expect,vi} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import raw from '../tests/fixtures/cockpit-budget-rules.json';
import pressure from '../tests/fixtures/cockpit-rule-pressure.json';
import base from '../tests/fixtures/cockpit-response.json';
import type {Catalog} from './types';
import type {CockpitSnapshot} from './cockpitTypes';
import {configPayload,configValidation,monthDayCount,budgetCurveRows,budgetCostRequest,type BudgetConfig,type RuleConfig} from './cockpitConfig';
import {CockpitBudget} from './CockpitBudget';
import {RuleEvaluationDetails} from './CockpitRuleEvaluation';
import {CockpitReturnStore,createNavigation,projectCockpitReport,readableNavigation} from './cockpitNavigation';
import {cockpitIssueNavigation} from './cockpitIssueProjection';
import {freezeCockpitExport,cockpitWorkbook} from './cockpitExports';
import {initializeLocale,changeLanguage,t} from './i18n';
const snapshot=raw.snapshot as unknown as CockpitSnapshot;
const view={selectedFace:'space' as const,presentationMode:false,scrollY:123,draft:{scope:snapshot.context.reportScope,categoryId:'c',preset:'custom' as const}};
const catalog:Catalog={project:snapshot.context.project,version:'test',spaceSource:'fin',user:{name:'u',canWrite:true},...raw.catalog,records:[...raw.catalog.records.map(row=>({...row,...(row.kind==='space'?{nativeReadonly:true}:row.kind==='meter'?{nativeTreeParentId:'s'}:{})})),{id:'np-p',kind:'nativePoint',name:'Primary point',nativeSourceId:'p',his:true}]} as Catalog;
it.each(['zh-CN','en-US'])('shows proven zero substitution and keeps old missing facts unknown in %s',language=>{
 initializeLocale(language);const evaluation=structuredClone(snapshot.modules.issues!.data!.ruleEvaluations![0]);
 const before=structuredClone(evaluation),html=renderToStaticMarkup(<RuleEvaluationDetails evaluation={evaluation} name={id=>id} open/>);
 expect(html).toContain(t('已观察到替代值的小时数'));expect(html).toContain(t('替代情况未完整核实的小时数'));
 expect(evaluation.inputs.substitutedNonWorkingHours).toBe(0);expect(evaluation.inputs.unknownSubstitutionNonWorkingHours).toBe(0);expect(html).not.toContain(t('此快照未提供'));expect(evaluation).toEqual(before);
 delete evaluation.inputs.substitutedNonWorkingHours;delete evaluation.inputs.unknownSubstitutionNonWorkingHours;
 const old=renderToStaticMarkup(<RuleEvaluationDetails evaluation={evaluation} name={id=>id} open/>);
 expect(old.split(t('此快照未提供')).length-1).toBe(2);
});
it('validates exact daily allocation, explicit zero, leap month and API business-field allowlist',()=>{
 vi.stubGlobal('localStorage',{getItem:()=>null,setItem:()=>{},removeItem:()=>{}});initializeLocale('zh-CN','quality-unit');expect(qualityLabel('currencyUnconfirmed')).toBe('费用币种无法确认');changeLanguage('en-US',{inPlace:true});expect(qualityLabel('currencyUnconfirmed')).toBe('Cost currency cannot be confirmed');changeLanguage('zh-CN',{inPlace:true});vi.unstubAllGlobals();initializeLocale('en-US','budget-test');expect(cockpitReasonText('COST_CURRENCY_MIXED')).toContain('Cost currencies');expect(cockpitReasonText('COST_CURRENCY_MIXED')).not.toContain('budget');const config:BudgetConfig={name:'Explicit daily',scopeKind:'project',scopeRef:'p:test',categoryRef:'c',enabled:true,month:'2026-10',currency:'CNY',amount:310000,distribution:'daily',dailyAmounts:[20000,0,...Array(29).fill(10000)]};
 expect(configValidation(config,'budget')).toBeUndefined();expect(monthDayCount('2024-02')).toBe(29);expect(monthDayCount('2026-02')).toBe(28);
 expect(configValidation({...config,dailyAmounts:[20000,0,...Array(28).fill(10000),9999]},'budget')).toContain('309,999');
 expect(configValidation({...config,amount:0},'budget')).toContain('greater than zero');expect(configValidation({...config,currency:'元'},'budget')).toContain('three uppercase');
 expect(configPayload({...config,id:'b',mod:'m',version:9,actor:'actor',canWrite:true,type:'budget'},'budget')).not.toHaveProperty('version');expect(configPayload({...config,distribution:'uniform'},'budget')).not.toHaveProperty('dailyAmounts');
 const rule:RuleConfig={name:'Explicit',scopeKind:'project',scopeRef:'p:test',categoryRef:'c',enabled:true,ruleType:'nonWorkingHighUsage',threshold:null,thresholdUnit:'kWh'};
 expect(configValidation(rule,'rule')).toContain('threshold');expect(configValidation({...rule,threshold:0},'rule')).toContain('calendar');expect(configValidation({...rule,threshold:0,calendarRef:'cal'},'rule')).toBeUndefined();
 expect(configPayload({...rule,ruleType:'budgetVariance',threshold:5,thresholdUnit:'%',currency:'CNY',calendarRef:'cal'},'rule')).not.toHaveProperty('calendarRef');
});
it('uses readable owned config revisions on return and preserves the original frozen snapshot on change',()=>{
 const store=new CockpitReturnStore(),nav=createNavigation(snapshot,'profile',view);store.save(catalog,nav,snapshot,view);
 expect(store.read(catalog,nav)?.configurationChanged).toBe(false);
 const changed={...catalog,cockpitConfigRefs:catalog.cockpitConfigRefs!.map(ref=>ref.id==='budget'?{...ref,mod:'b2'}:ref)};
 const restored=store.read(changed,nav)!;expect(restored.configurationChanged).toBe(true);expect(restored.snapshot.modules.kpis?.data?.budget?.configRefs?.[0].mod).toBe('b1');
 expect(restored.snapshot.snapshotId).toBe(snapshot.snapshotId);
 const legacy=structuredClone(base) as CockpitSnapshot,legacyCatalog={...catalog,records:[{id:'s',kind:'space' as const,name:'Site',nativeReadonly:true},{id:'c',kind:'category' as const,name:'Energy'},...['a','b'].map(id=>({id,kind:'meter' as const,name:id})),...['pa','pb'].map(id=>({id,kind:'nativePoint' as const,name:id,his:true}))]};store.save(legacyCatalog,createNavigation(legacy,'profile',view),legacy,view);
 expect(legacy.provenance.configRefs.every(ref=>!ref.id.includes('budget'))).toBe(true);
});
it('projects exact canonical cost evidence without substituting energy or a view cost report',()=>{
 const request=budgetCostRequest(snapshot)!;expect(request.metric).toBe('cost');const result=projectCockpitReport(snapshot,request)!;
 expect(result.request.metric).toBe('cost');expect(result.result).toEqual(snapshot.reports['budget-canonical-cost']);
 const p=pressure as unknown as CockpitSnapshot,item=p.modules.issues!.data!.items.find(row=>row.type==='ruleClue'&&row.ruleType==='budgetVariance')!,navigation=cockpitIssueNavigation(p,item,view)!;
 expect(navigation.targetRequest.metric).toBe('cost');expect(navigation.parentSnapshotId).toBe(p.snapshotId);expect(projectCockpitReport(p,navigation.targetRequest)?.result).toEqual(p.reports['budget-canonical-cost']);
 expect(readableNavigation(catalog,navigation)).toBe(true);expect(cockpitIssueNavigation(p,{...item,evidenceTarget:{...item.evidenceTarget!,parentSnapshotId:'other'}},view)).toBeUndefined();
});
it('retains server supplied three independent rates and missing/zero semantics in both languages',()=>{
 const s=structuredClone(snapshot),b=s.modules.kpis!.data!.budget!;Object.assign(b,{monthBudget:310000,periodBudget:240000,periodActualCost:224600,deviationAmount:-15400,variancePct:-6.4166666667,monthUsagePct:72.4516129,calendarProgressPct:77.4193548});
 for(const language of ['zh-CN','en-US']){initializeLocale(language,'budget-test');const html=renderToStaticMarkup(<CockpitBudget snapshot={s}/>);expect(html).toContain('310,000');expect(html).toContain('240,000');expect(html).toContain('224,600');expect(html).toContain('-6.42');expect(html).toContain('72.45');expect(html).toContain('77.42');expect(html).not.toContain('BUDGET_');}
 Object.assign(b,{status:'unavailable',reasonCodes:['BUDGET_CURRENCY_MISMATCH'],periodBudget:null,periodActualCost:0,variancePct:null,curve:[]});const html=renderToStaticMarkup(<CockpitBudget snapshot={s}/>);expect(html).toContain('currencies differ');expect(html).not.toContain('NaN');expect(b.periodActualCost).toBe(0);Object.assign(b,{status:'ok',budgetStatus:'ok',comparisonStatus:'unavailable',reasonCodes:['BUDGET_ZERO_PERIOD'],monthBudget:310000,periodBudget:0,periodActualCost:0,monthUsagePct:0});const zero=renderToStaticMarkup(<CockpitBudget snapshot={s}/>);expect(zero).toContain('Period budget is zero');expect(zero).not.toContain('Configure budget for this scope');expect(zero).not.toContain('Contact the project administrator');expect(zero).toContain('0');Object.assign(b,{status:'unavailable',budgetStatus:'unavailable',comparisonStatus:'unavailable',reasonCodes:['BUDGET_NOT_CONFIGURED'],monthBudget:null,periodBudget:null,periodActualCost:null});const compact=renderToStaticMarkup(<CockpitBudget snapshot={s}/>);expect(compact).not.toContain('cockpit-budget-values');expect(compact).not.toContain('<progress');expect(compact).toContain('No matching budget');
});
it('draws cost only at closed canonical buckets and preserves NA gaps instead of daily interpolation',()=>{
 const s=structuredClone(snapshot),b=s.modules.kpis!.data!.budget!,r=s.reports[b.costReportRef!],p=r.series[0].points[0];b.curve=[{ts:r.from,periodBudget:0,cumulativeBudget:0},{ts:'2026-10-01T00:30:00Z',periodBudget:1,cumulativeBudget:1},{ts:r.to,periodBudget:1,cumulativeBudget:2}];
 expect(budgetCurveRows(s).map(row=>row.actualCost)).toEqual([0,null,10]);p.value=0;p.completeValue=0;expect(budgetCurveRows(s).at(-1)?.actualCost).toBe(0);p.value=null;p.valueType='na';expect(budgetCurveRows(s).at(-1)?.actualCost).toBeNull();expect(snapshot.reports[b.costReportRef!].series[0].points[0].value).toBe(10);
});
it('freezes budget, calendar and rule inputs into numeric workbook sheets and old JSON without later mixing',async()=>{
 initializeLocale('en-US','budget-test');const s=structuredClone(pressure) as CockpitSnapshot,packet=freezeCockpitExport(s,'en-US',{}),old=JSON.stringify(packet);
 s.modules.kpis!.data!.budget!.periodActualCost=9999;s.modules.issues!.data!.ruleEvaluations![0].threshold=9999;expect(JSON.stringify(packet)).toBe(old);
 const book=await cockpitWorkbook(packet);expect(book.getWorksheet('Budget operating reference')?.getRow(4).getCell(2).value).toBe(10);expect(book.getWorksheet('Rule evaluations')?.rowCount).toBe(3);
 const html=renderToStaticMarkup(<RuleEvaluationDetails evaluation={packet.snapshot.modules.issues!.data!.ruleEvaluations![1]} name={id=>id} open/>);expect(html).toContain('FIN alarms');expect(html).toContain('Greater than');expect(html).toContain('periodBudget');
},20000);
