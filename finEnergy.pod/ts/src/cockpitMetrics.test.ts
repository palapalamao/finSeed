import {afterEach,expect,it} from 'vitest';
import {initializeLocale} from './i18n';
import type {Catalog} from './types';
import type {CockpitMetric,CockpitSnapshot} from './cockpitTypes';
import fixture from '../tests/fixtures/cockpit-metrics-response.json';
import {cockpitAuxiliaryCategory,cockpitCards,cockpitComparisonText,cockpitConclusionText,cockpitMetricValue} from './cockpitMetrics';

afterEach(()=>initializeLocale('zh-CN'));
it('renders the actual Fantom KPI result in the frozen four-card order without recalculating percentages',()=>{
 initializeLocale('en-US');
 const snapshot=structuredClone(fixture) as unknown as CockpitSnapshot,before=structuredClone(snapshot);
 expect(cockpitCards(snapshot).map(card=>[card.id,cockpitMetricValue(card)])).toEqual([['cost','200'],['energy','100'],['auxiliaryEnergy','8'],['co2','70']]);
 expect(cockpitComparisonText(cockpitCards(snapshot)[1])).toContain('+25%');
 expect(cockpitConclusionText(snapshot.modules.kpis!.data!.conclusions[0])).toContain('+25%');
 expect(snapshot).toEqual(before);
});
it('preserves real zero and NA and obeys backend suppression of incomplete comparisons',()=>{
 initializeLocale('en-US');
 const metric=structuredClone(fixture.modules.kpis.data.values[0]) as unknown as CockpitMetric&{comparison:NonNullable<CockpitMetric['comparison']>};
 metric.value=0;metric.comparison.reference=0;metric.comparison.changeRate=null;metric.comparison.reasonCodes=['ZERO_REFERENCE'];
 expect(cockpitMetricValue(metric)).toBe('0');expect(cockpitComparisonText(metric)).toContain('zero');expect(cockpitComparisonText(metric)).not.toContain('%');
 metric.comparison.reference=80;metric.comparison.current=100;metric.comparison.comparable=false;metric.comparison.changeRate=25;metric.comparison.reasonCodes=['INCOMPLETE_COVERAGE'];
 expect(cockpitComparisonText(metric)).not.toContain('25%');
 expect(cockpitMetricValue({...metric,value:null,valueType:'na'})).toBe('NA');
 expect(cockpitMetricValue({...metric,value:null,valueType:'null'})).toBe('—');
});
it('uses bound primary-point water tags instead of category names or a bare cubic-metre unit',()=>{
 const catalog:Catalog={version:'test',project:'test',user:{name:'test',canWrite:false},records:[{kind:'category',id:'electric',name:'电',unit:'kWh'},{kind:'category',id:'gas',name:'Water',unit:'m3'},{kind:'category',id:'water',name:'用户原始名称',unit:'m3'},{kind:'meter',id:'gasMeter',name:'Gas meter',categoryId:'gas',pointId:'gasPoint'},{kind:'meter',id:'waterMeter',name:'Water meter',categoryId:'water',pointId:'waterPoint'},{kind:'nativePoint',id:'native-water',nativeSourceId:'waterPoint',name:'流量',his:true,energyTags:['water']}]};
 expect(cockpitAuxiliaryCategory(catalog,'electric')).toBe('water');
 catalog.records=catalog.records.filter(row=>row.id!=='waterMeter');expect(cockpitAuxiliaryCategory(catalog,'electric')).toBeUndefined();
});
it('renders service fallback cards and traceable conclusions without treating events as interval energy',()=>{
 initializeLocale('en-US');const snapshot=structuredClone(fixture) as unknown as CockpitSnapshot;
 snapshot.modules.kpis!.data!.values=snapshot.modules.kpis!.data!.values.map(metric=>metric.id==='auxiliaryEnergy'?{...metric,id:'areaIntensity',value:null,valueType:'null',valueBasis:'unavailable',reasonCodes:['missingArea']}:metric.id==='co2'?{...metric,id:'activeAlarms',value:0,valueBasis:'currentState',unit:'count',stateObservedAt:'2026-10-31T12:00:00Z'}:metric);
 expect(cockpitCards(snapshot).map(card=>card.id)).toEqual(['cost','energy','areaIntensity','activeAlarms']);
 expect(cockpitMetricValue(cockpitCards(snapshot)[3])).toBe('0');
 expect(cockpitConclusionText({id:'q',ruleId:'CPT02-dataQuality',ruleVersion:1,messageKey:'cockpit.conclusion.dataQuality',args:{metricId:'areaIntensity',reasonCodes:['missingArea']},evidenceRefs:[],priority:1})).toContain('area');
});
