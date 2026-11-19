import {afterEach,describe,expect,it,vi} from 'vitest';
import {cleaningDraft,cleaningParameters,previewRangeError} from './cleaning';
import {filterSnapshot,makeSnapshot,reportTables} from './exports';
import {profileStats,reportCellText} from './reportDisplay';
import type {ReportRequest,ReportResult} from './types';

describe('cleaning profile form contract',()=>{
 it('defaults to nonnegative deltas and a one hour gap without an arbitrary maximum',()=>{
  expect(cleaningParameters(cleaningDraft())).toEqual({deltaMin:0,timeMax:'1h',defNull:true});
 });
 it('omits disabled or cleared rules and encodes explicit units',()=>{
  const draft=cleaningDraft();draft.deltaMin.enabled=false;draft.timeMax='';draft.deltaMax={enabled:true,value:100,unit:'kWh'};draft.removeNA=false;
  expect(cleaningParameters(draft)).toEqual({deltaMax:{type:'number',value:100,unit:'kWh'},defNull:true});
 });
 it('keeps filter, replacement and counter rollover modes mutually exclusive',()=>{
  const draft=cleaningDraft();draft.mode='replace';draft.defVal={enabled:true,value:0,unit:'kWh'};
  expect(cleaningParameters(draft)).toEqual({deltaMin:0,timeMax:'1h',defVal:{type:'number',value:0,unit:'kWh'}});
  draft.defValNA=true;expect(cleaningParameters(draft).defVal).toEqual({type:'na'});
  draft.mode='rollover';draft.hisTotalizedRollover={enabled:true,value:32768,unit:'kWh'};draft.deltaMax={enabled:true,value:100,unit:'kWh'};
  expect(cleaningParameters(draft)).toEqual({deltaMin:0,deltaMax:{type:'number',value:100,unit:'kWh'},timeMax:'1h',hisTotalizedRollover:{type:'number',value:32768,unit:'kWh'}});
 });
 it('rejects reversed bounds and rollover without an upper bound',()=>{
  const draft=cleaningDraft();draft.deltaMin.value=10;draft.deltaMax={enabled:true,value:5,unit:''};
  expect(()=>cleaningParameters(draft)).toThrow('最小值不能大于最大值');
  draft.deltaMax.enabled=false;draft.mode='rollover';draft.hisTotalizedRollover.value=32768;
  expect(()=>cleaningParameters(draft)).toThrow('回绕模式需要计数周期和增量上限或变化率上限');
 });
 it('round trips persisted typed values and markers without converting off markers to false',()=>{
  const profile={kind:'cleaningProfile',name:'按表计配置',mode:'replace',parameters:{derivMax:{type:'number',value:20,unit:'kW'},defVal:{type:'na'},removeNA:true}};
  expect(cleaningParameters(cleaningDraft(profile))).toEqual(profile.parameters);
 });
 it('bounds previews to a valid single range no longer than 31 days',()=>{
  expect(previewRangeError('2026-10-01','2026-10-02')).toBeUndefined();
  expect(previewRangeError('2026-10-02','2026-10-01')).toBeTruthy();
  expect(previewRangeError('2026-01-01','2026-03-01')).toBeTruthy();
 });
});

describe('cleaning report evidence',()=>{
 const request:ReportRequest={kind:'profile',nodeIds:['meter'],from:'2026-10-01T00:00:00+08:00',to:'2026-10-02T00:00:00+08:00',metric:'energy',period:'day',perArea:false};
 const result:ReportResult={kind:'profile',from:request.from,to:request.to,period:'day',series:[{id:'meter',name:'电表',categoryId:'cat',unit:'kWh',points:[{ts:request.from,value:null,valueType:'na',quality:'substituted',sourceIds:['p']}]}],rows:[{nodeId:'meter',categoryId:'cat',value:null,valueType:'na',quality:'substituted'}],summary:{},warnings:[],extra:{cleaning:[{pointId:'p',profileId:'profile',profileVersion:3,parameters:{deltaMin:0,defNull:true},sourceIds:['p'],summary:{filteredCount:2,substitutedCount:1,coverage:75},details:[]}]}};
 it('distinguishes NA from missing data and exports cleaning quality',()=>{
  const s=makeSnapshot(request,result,'概况','p');
  expect(reportCellText(s,'value',null,false,result.rows[0])).toBe('NA');
  expect(reportTables(s).series[1][3]).toBe('NA');
  expect(reportCellText(s,'quality','filtered')).toBe('有效用量小计');
  expect(reportCellText(s,'quality','substituted')).toBe('清洗后用量，含替代值');
 });
 it('retains profile snapshots and details when filtering an export by category',()=>{
  const s=makeSnapshot(request,result,'概况','p');
  expect(filterSnapshot(s,['cat'],['电力'])!.result.extra!.cleaning).toEqual(result.extra!.cleaning);
 });
 it('uses numeric filtered and substituted buckets for available-data means and maxima',()=>{
  for(const quality of ['filtered','substituted']){
   const s=makeSnapshot(request,result,'概况','p');s.result.series[0].points=[{ts:request.from,value:5,quality,sourceIds:['p']}];s.result.summary={totals:[{id:'meter',value:5,quality}]};
   const stats=profileStats(s,s.result.series[0]);expect(stats.total).toBe(5);expect(stats.average).toBe(5);expect(stats.peak).toBe(5);expect(stats.partial).toBe(1);
  }
 });
 it('counts cleaned and corrected values as reliable and labels their quality',()=>{
  for(const quality of ['cleaned','corrected']){
   const s=makeSnapshot(request,result,'概况','p');s.result.series[0].points=[{ts:request.from,value:5,quality,sourceIds:['p']}];s.result.summary={totals:[{id:'meter',value:5,quality}]};
   const stats=profileStats(s,s.result.series[0]);expect(stats.average).toBe(5);expect(stats.peak).toBe(5);expect(reportCellText(s,'quality',quality)).not.toContain('数据异常');
  }
 });
});
describe('cleaning service errors',()=>{
 afterEach(()=>{vi.unstubAllGlobals();vi.resetModules();});
 it.each(['zh-CN','en-US'])('localizes diagnostic fields and booleans for %s without changing numeric evidence',async(language)=>{
  vi.resetModules();(await import('./i18n')).initializeLocale(language);
  const {reportLabels,reportCellText,readableReportValue}=await import('./reportDisplay');
  const {makeSnapshot}=await import('./exports');
  const request:ReportRequest={kind:'profile',nodeIds:['meter'],from:'2026-10-04T00:00:00+08:00',to:'2026-10-04T02:00:00+08:00',metric:'energy',period:'hour',perArea:false};
  const result:ReportResult={kind:'profile',from:request.from,to:request.to,period:'hour',series:[],rows:[],summary:{},warnings:[]};
  const snapshot=makeSnapshot(request,result,'清洗测试','test');const zh=language==='zh-CN';
  expect(['previousValue','emitted','substituted','intervalSeconds'].map(key=>reportLabels[key])).toEqual(zh?['前一读数','是否输出','是否替代','区间时长（秒）']:['Previous reading','Output emitted','Value substituted','Interval duration (seconds)']);
  for(const key of ['emitted','substituted']){expect(reportCellText(snapshot,key,true)).toBe(zh?'是':'Yes');expect(reportCellText(snapshot,key,false)).toBe(zh?'否':'No');}
  const detail={previousValue:32760,emitted:true,substituted:false,intervalSeconds:3600};
  expect(readableReportValue(snapshot,'',detail)).toEqual(zh?{'前一读数':32760,'是否输出':'是','是否替代':'否','区间时长（秒）':3600}:{'Previous reading':32760,'Output emitted':'Yes','Value substituted':'No','Interval duration (seconds)':3600});
  expect(detail).toEqual({previousValue:32760,emitted:true,substituted:false,intervalSeconds:3600});
 });
 it.each(['zh-CN','en-US'])('localizes processing counts in reports for %s',async(language)=>{
  vi.resetModules();(await import('./i18n')).initializeLocale(language);const {reportLabels}=await import('./reportDisplay');
  const expected=language==='zh-CN'?['输出读数数','空值数','拒绝数','回绕数','已移除 NA 数','诊断明细已截断']:['Output readings','Null count','Rejected count','Rollover count','Removed NA count','Diagnostics truncated'];
  expect(['outputCount','nullCount','rejectedCount','rolloverCount','removedNACount','detailsTruncated'].map(key=>reportLabels[key])).toEqual(expected);
  const {cleaningScopeText,cleaningReason}=await import('./cleaning');
  expect(cleaningReason('deltaMin')).toBe(language==='zh-CN'?'低于最小增量':'Below minimum delta');
  expect(cleaningScopeText('sourceIntervals')).toBe(language==='zh-CN'?'源点区间处理次数；输出点数和覆盖率按当前对象计算':'Source interval processing counts; output readings and coverage describe the current object');
 });
 it('localizes core validation and source failures for Chinese users',async()=>{
  vi.resetModules();(await import('./i18n')).initializeLocale('zh-CN');const {serverMessage}=await import('./i18n');
  expect(serverMessage('deltaMax unit is incompatible with kWh')).toBe('deltaMax 的单位与 kWh 不兼容');
  expect(serverMessage('missingCleaningProfile')).toBe('清洗方案缺失，或源点未由此方案管理');
  expect(serverMessage('History exceeds 1000000 raw samples')).toContain('请缩短查询范围');
 });
 it('localizes repository and source failures for English users',async()=>{
  vi.resetModules();(await import('./i18n')).initializeLocale('en-US');const {serverMessage}=await import('./i18n');
  expect(serverMessage('清洗点位原生标签类型无效')).toBe('The cleaning point has invalid native tag types.');
  expect(serverMessage('missingSource')).toBe('The cleaning source point or equipment is missing or cannot be read.');
  expect(serverMessage('externalFunctionManaged')).toBe('Managed by an external function.');
 });
});
