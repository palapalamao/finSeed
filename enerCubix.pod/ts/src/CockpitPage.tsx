import {useEffect,useMemo,useRef,useState,useSyncExternalStore,useCallback} from 'react';
import {Alert,Button,Empty,Select,Spin,Tag} from 'antd';
import {ReloadOutlined} from '@ant-design/icons';
import type {EnerCubixApi} from './api';
import type {Catalog} from './types';
import {cockpitModules,type CockpitFace,type CockpitRequest,type CockpitScope} from './cockpitTypes';
import {CockpitQuery,defaultCockpitSelection,cockpitQueryError} from './cockpitQuery';
import {dimensionRecords} from './dimensionTree';
import {ReportChart} from './ReportView';
import {locale,t} from './i18n';
import {reportQualityText} from './reportQuality';
import {cockpitProfileSnapshot,cockpitCompleteValue} from './cockpitReport';
import {absoluteCockpitRequest,createFaceNavigation,createNavigation,type CockpitTargetKind,focusRecords,type CockpitReturnState,type CockpitViewState,type NavigationContextV1} from './cockpitNavigation';
import {CockpitKpis} from './CockpitKpis';
import {CockpitDates,type CockpitDateDraft} from './CockpitDates';
import {cockpitAuxiliaryCategory} from './cockpitMetrics';
import {CockpitMain} from './CockpitMain';
import {CockpitFlow} from './CockpitFlow';
import {CockpitSpace} from './CockpitSpace';
import {CockpitReference} from './CockpitReference';
import {CockpitBrief,CockpitNextSteps} from './CockpitBrief';
import {cockpitSpaceObjects} from './cockpitSpaceProjection';
import {cockpitCopNavigation} from './cockpitEfficiencyProjection';
import {CockpitIssues} from './CockpitIssues';
import {CockpitPresentation} from './CockpitPresentation';
import {cockpitIssueNavigation} from './cockpitIssueProjection';
import {useCockpitRefresh,CockpitRefreshControls,refreshStatus} from './CockpitRefresh';
import {DiagnosticNotice} from './DiagnosticNotice';
import type {CockpitAssetEvidence} from './cockpitAssets';
import './cockpit.css';
import './cockpitP01.css';

// Keep the legacy dashboard route available throughout incremental delivery.
export const cockpitEnabled=true;
function time(value:string|null|undefined){return value?value.replace('T',' '):t('暂无数据');}
export function CockpitPage({api,catalog,onLegacy,onConfigure,onConfigureAssets,initialRequest,restored,initialView,onDrill,onSnapshot,onExportLock}:{onExportLock?:(value:boolean)=>void;initialView?:{focusObjectId?:string;selectedFace:CockpitFace;presentationMode:boolean;scrollY:number};onSnapshot?:(snapshot:import('./cockpitTypes').CockpitSnapshot,view:CockpitViewState)=>void;initialRequest?:CockpitRequest;restored?:CockpitReturnState;onDrill:(navigation:NavigationContextV1,snapshot:import('./cockpitTypes').CockpitSnapshot,view:CockpitViewState)=>void;api:EnerCubixApi;catalog:Catalog;onLegacy:()=>void;onConfigure:()=>void;onConfigureAssets?:()=>void}){
 const selection=useMemo(()=>defaultCockpitSelection(catalog),[catalog]);
 const [conditionsOpen,setConditionsOpen]=useState(false);
 const [assetEvidence,setAssetEvidence]=useState<CockpitAssetEvidence>();
 const [scope,setScope]=useState<CockpitScope|undefined>(()=>restored?.view.draft.scope||initialRequest?.reportScope||selection?.scope);
 const [focusObjectId,setFocusObjectId]=useState(restored?.view.focusObjectId||initialView?.focusObjectId);
 const [presentationMode,setPresentationMode]=useState(restored?.view.presentationMode??initialView?.presentationMode??false);
 const [face,setFace]=useState<CockpitFace>(restored?.view.selectedFace||initialView?.selectedFace||'space');
 const [categoryId,setCategoryId]=useState(restored?.view.draft.categoryId||initialRequest?.focusCategoryId||selection?.categoryId);
 const [preset,setPreset]=useState<CockpitRequest['time']['preset']>(restored?.view.draft.preset||initialRequest?.time.preset||'thisMonth');
 const [auxiliarySelection,setAuxiliarySelection]=useState<string|undefined>(()=>restored?(restored.view.draft.auxiliarySelection??restored.snapshot.context.auxiliaryCategoryId??'__area__'):initialRequest?(initialRequest.auxiliaryCategoryId??'__area__'):undefined);
 const auxiliaryCategoryId=auxiliarySelection==='__area__'?undefined:auxiliarySelection||cockpitAuxiliaryCategory(catalog,categoryId||'',scope);
 const [dates,setDates]=useState<CockpitDateDraft>(()=>restored?.view.draft.dates||{from:initialRequest?.time.from,to:initialRequest?.time.to,period:initialRequest?.time.period||'day',comparison:restored?.snapshot.context.comparison||initialRequest?.comparison||{mode:'presetDefault'}});
 const sequence=useRef(0);
 const presentationScroll=useRef<number|undefined>(undefined);
 const changeMode=(value:boolean)=>{if(value&&!presentationMode)presentationScroll.current=window.scrollY;setPresentationMode(value);if(!value&&presentationScroll.current!==undefined)requestAnimationFrame(()=>window.scrollTo(0,presentationScroll.current!));};
 const query=useMemo(()=>new CockpitQuery((request,signal)=>api.cockpit(request,signal)),[api]);
 const state=useSyncExternalStore(query.subscribe,query.getSnapshot,query.getSnapshot);
 const automatic=useCockpitRefresh(query,catalog.user.name,catalog.project);
 const handleExportLock=useCallback((value:boolean)=>{automatic.controller.setPaused('export',value);onExportLock?.(value);},[automatic.controller,onExportLock]);
 // Explicit Apply/Refresh obtains a fresh observation cutoff. Restore and scope promotion use absoluteCockpitRequest instead.
 const makeRequest=():CockpitRequest|undefined=>selection&&scope&&categoryId?{schemaVersion:1,requestId:'cockpit-'+(++sequence.current),reportScope:scope,focusCategoryId:categoryId,...(auxiliaryCategoryId?{auxiliaryCategoryId}:{}),time:preset==='custom'?{preset,period:dates.period,from:dates.from,to:dates.to}:{preset,period:preset==='today'?'hour':preset==='thisYear'?'month':'day'},comparison:dates.comparison.mode==='custom'?dates.comparison:{mode:dates.comparison.mode},modules:[...cockpitModules]}:undefined;
 const apply=()=>{const request=makeRequest();if(request)void query.apply(request);};
 useEffect(()=>{if(restored){query.restore(restored.snapshot);requestAnimationFrame(()=>window.scrollTo(0,restored.view.scrollY));}else if(initialRequest){void query.apply({...initialRequest,requestId:'restore-'+(++sequence.current)});}else if(selection&&query.getSnapshot().phase==='idle'){void query.apply({schemaVersion:1,requestId:'initial-'+(++sequence.current),reportScope:selection.scope,focusCategoryId:selection.categoryId,...(auxiliaryCategoryId?{auxiliaryCategoryId}:{}),time:{preset:'thisMonth',period:'day'},comparison:{mode:'presetDefault'},modules:[...cockpitModules]});}return()=>query.cancel();},[query]);
 const snapshot=state.snapshot,report=useMemo(()=>snapshot?cockpitProfileSnapshot(snapshot):undefined,[snapshot,locale]);
 useEffect(()=>{if(snapshot)setDates(current=>current.from&&current.to?current:{...current,from:snapshot.context.time.from,to:snapshot.context.time.to});},[snapshot]);
 const dateInvalid=preset==='custom'&&(!dates.from||!dates.to||Date.parse(dates.from)>=Date.parse(dates.to))||dates.comparison.mode==='custom'&&(!dates.comparison.from||!dates.comparison.to||Date.parse(dates.comparison.from)>=Date.parse(dates.comparison.to));
 const loading=state.phase==='loading'||state.phase==='refreshing';
 const scopeRows=dimensionRecords(catalog.records,scope?.dimension||'space',catalog.spaceSource==='fin').filter(r=>r.id&&!r.nativeHidden&&['space','organization','meter','totalMeter'].includes(r.kind));
 const categories=catalog.records.filter(r=>r.kind==='category'&&r.id);
 const sameComparison=!!snapshot&&((preset==='custom'&&dates.comparison.mode==='presetDefault'?'none':dates.comparison.mode)===(snapshot.context.comparison?.mode||'none')&&(dates.comparison.mode!=='custom'||Date.parse(dates.comparison.from||'')===Date.parse(snapshot.context.comparison?.from||'')&&Date.parse(dates.comparison.to||'')===Date.parse(snapshot.context.comparison?.to||'')));
 const dirty=!!snapshot&&(scope?.dimension!==snapshot.context.reportScope.dimension||scope?.selectionIntent!==snapshot.context.reportScope.selectionIntent||JSON.stringify(scope?.nodeIds)!==JSON.stringify(snapshot.context.reportScope.nodeIds)||categoryId!==snapshot.context.focusCategoryId||auxiliaryCategoryId!==(snapshot.context.auxiliaryCategoryId??undefined)||preset!==snapshot.context.time.preset||!sameComparison||preset==='custom'&&(Date.parse(dates.from||'')!==Date.parse(snapshot.context.time.from)||Date.parse(dates.to||'')!==Date.parse(snapshot.context.time.to)||dates.period!==snapshot.context.time.period));
 const name=(id:string)=>catalog.records.find(r=>r.id===id)?.name||id;
 const hasChart=report?.result.series.some(series=>series.points.some(point=>point.value!==null||point.knownValue!=null));
 const focusRows=snapshot&&snapshot.capabilities.canRead?focusRecords(catalog,snapshot.context.reportScope):[];
 const focused=focusRows.find(r=>r.id===focusObjectId),spaceFocus=snapshot?cockpitSpaceObjects(snapshot,catalog).find(node=>node.id===focusObjectId):undefined;
 const selectedFocusId=focused?.id||spaceFocus?.id;
 const currentView=():CockpitViewState=>({focusObjectId:selectedFocusId,selectedFace:face,presentationMode,scrollY:window.scrollY,draft:{scope:scope!,categoryId:categoryId!,preset,auxiliarySelection:auxiliarySelection||auxiliaryCategoryId||'__area__',dates}});
 const drill=(kind:'profile'|'energyFlow')=>{if(!snapshot)return;automatic.controller.setPaused('route',true);const view=currentView();onDrill(createNavigation(snapshot,kind,view),snapshot,view);};
 const drillFace=(kind:Exclude<CockpitTargetKind,'energyFlow'>)=>{if(!snapshot)return;automatic.controller.setPaused('route',true);const view=currentView();onDrill(createFaceNavigation(snapshot,kind,view),snapshot,view);};
 useEffect(()=>{if(snapshot&&scope&&categoryId)onSnapshot?.(snapshot,currentView());},[snapshot,face,selectedFocusId,presentationMode]);
 const setStatisticalScope=()=>{if(!selectedFocusId||!snapshot)return;const next:CockpitScope={dimension:snapshot.context.reportScope.dimension,nodeIds:[selectedFocusId],selectionIntent:spaceFocus?.basis==='ownPrimary'||!!focused&&['meter','totalMeter'].includes(focused.kind)?'explicitObjects':'range'};const applied=absoluteCockpitRequest(snapshot);setScope(next);setFocusObjectId(undefined);setCategoryId(applied.focusCategoryId);setAuxiliarySelection(applied.auxiliaryCategoryId||'__area__');setPreset('custom');setDates({from:applied.time.from,to:applied.time.to,period:applied.time.period,comparison:applied.comparison||{mode:'none'}});void query.apply({...applied,requestId:'scope-'+(++sequence.current),reportScope:next});};
 return <main className={presentationMode?"cockpit-page cockpit-presentation":"cockpit-page"} aria-labelledby="cockpit-title">
  <header className="cockpit-heading"><div>{snapshot&&<p className="cockpit-project-line">{t('FIN 项目：{0}',snapshot.context.project)} / {snapshot.context.reportScope.nodeIds.map(name).join(' / ')} · {name(snapshot.context.focusCategoryId)}</p>}<h2 id="cockpit-title">{t('能源经营驾驶舱')}</h2>{snapshot?<div className="cockpit-context"><p>{time(snapshot.context.time.from).slice(0,16)} — {time(snapshot.context.time.to).slice(0,16)} · {snapshot.context.projectTimeZone}</p><p>{t('结束时间不含 · 快照 {0}',time(snapshot.generatedAt).slice(0,16))}</p></div>:<p>{t('从真实用量开始，定位范围并核对数据依据。')}</p>}</div><div className="cockpit-heading-actions">{selection&&<><Button className="cockpit-conditions-trigger" aria-label={t('统计范围与条件')} aria-expanded={conditionsOpen} aria-controls="cockpit-query-fields" onClick={()=>setConditionsOpen(value=>!value)}>{t('统计范围')}</Button><Button className="cockpit-query-submit" aria-label={dirty?t('应用条件'):t('刷新数据')} title={dirty?t('应用条件'):t('刷新数据')} icon={dirty?undefined:<ReloadOutlined/>} type={dirty?'primary':'default'} disabled={state.phase==='sessionExpired'||!scope?.nodeIds.length||!!dateInvalid} onClick={apply}>{dirty?t('应用条件'):null}</Button>{dirty&&<Tag className="cockpit-query-state">{t('条件尚未应用')}</Tag>}</>}{!snapshot&&<Button onClick={()=>{automatic.controller.setPaused('route',true);onLegacy();}}>{t('旧版总览')}</Button>}{snapshot&&<CockpitPresentation more={<Button onClick={()=>{automatic.controller.setPaused('route',true);onLegacy();}}>{t('旧版总览')}</Button>} assetEvidence={assetEvidence} snapshot={snapshot} objects={Object.fromEntries(catalog.records.filter(r=>r.id).map(r=>[r.id!,r.name]))} presentationMode={presentationMode} onMode={changeMode} onLock={handleExportLock} loading={loading}/>}{automatic.state.minutes>0&&<span className="cockpit-auto-status" role="status">{refreshStatus(automatic.state)}</span>}</div></header>
  {!selection?<section className="cockpit-empty"><Empty description={t('尚无可分析的主能耗点配置')}/><p>{t('请先选择设备、绑定主能耗点并配置能源分类。')}</p>{catalog.user.canWrite?<Button onClick={()=>{automatic.controller.setPaused('route',true);onConfigure();}}>{t('配置计量资产')}</Button>:<p>{t('请联系项目管理员完善配置。')}</p>}</section>:<>
   <section hidden={!conditionsOpen} id="cockpit-query-fields" className="cockpit-controls" aria-label={t('驾驶舱查询条件')}>
    <div className="cockpit-controls-primary"><label>{t('统计范围')}<Select aria-label={t('统计范围')} mode="multiple" maxTagCount={1} value={scope?.nodeIds} onChange={nodeIds=>setScope(current=>({...current!,nodeIds}))} options={scopeRows.map(r=>({value:r.id,label:r.name}))}/></label>
    <label>{t('关注能源')}<Select aria-label={t('关注能源')} value={categoryId} onChange={value=>{setCategoryId(value);setAuxiliarySelection(undefined);}} options={categories.map(r=>({value:r.id,label:r.name}))}/></label>
    <label>{t('统计时间')}<Select aria-label={t('统计时间')} value={preset} onChange={setPreset} options={[{value:'today',label:t('今日')},{value:'thisMonth',label:t('本月')},{value:'thisYear',label:t('本年')},{value:'custom',label:t('自定义时间')}]}/></label>
    </div>
    <details className="cockpit-controls-more" open={preset==='custom'||undefined}><summary>{t('更多条件与比较')}</summary><div className="cockpit-controls-advanced">
    <label>{t('范围选择方式')}<Select aria-label={t('范围选择方式')} value={scope?.selectionIntent} onChange={selectionIntent=>setScope(current=>({...current!,selectionIntent}))} options={[{value:'range',label:t('范围')},{value:'explicitObjects',label:t('明确对象')}]}/></label>
    <label>{t('辅助能源')}<Select aria-label={t('辅助能源')} value={auxiliaryCategoryId||'__area__'} onChange={setAuxiliarySelection} options={[{value:'__area__',label:t('单位面积用量')},...categories.filter(category=>category.id!==categoryId&&catalog.records.some(meter=>['meter','totalMeter'].includes(meter.kind)&&meter.pointId&&meter.categoryId===category.id)).map(category=>({value:category.id!,label:category.name}))]}/></label>
    <CockpitDates preset={preset} draft={dates} onChange={setDates}/><CockpitRefreshControls controller={automatic.controller} state={automatic.state}/></div></details>
   </section>
   <div aria-live="polite">{loading&&<p className="cockpit-loading"><Spin size="small"/> {t('正在读取驾驶舱数据…')}</p>}{state.error&&<Alert type="error" showIcon message={cockpitQueryError(state)}/>}</div>
   {snapshot&&<section className="cockpit-snapshot" data-cockpit-snapshot={snapshot.snapshotId} aria-label={t('驾驶舱数据快照')}>
    {(state.phase!=='ready'||dirty)&&<Alert type="info" showIcon message={t('当前保留上次成功快照，范围和时间以此处标注为准。')}/>}
    {initialRequest&&!restored&&<Alert type="info" showIcon message={t('已恢复绝对查询条件并重新读取，这是新快照。')}/>}
    {restored?.configurationChanged&&<Alert type="warning" showIcon message={t('当前配置已变化；此处保留原快照，重新查询将使用当前配置。')}/>}
    {presentationMode&&<CockpitBrief snapshot={snapshot} catalog={catalog} onProfile={()=>drill('profile')} onFlow={()=>drill('energyFlow')}/>}
    <CockpitKpis snapshot={snapshot} name={name}/>
    <CockpitMain snapshot={snapshot} face={face} onFace={setFace} onReport={drillFace} name={name} focusObjectId={selectedFocusId} onFlow={()=>drill('energyFlow')} onCop={id=>{const view=currentView();onDrill(cockpitCopNavigation(snapshot,id,view),snapshot,view);}}
     reference={<CockpitReference snapshot={snapshot}/>}
     space={<CockpitSpace api={api} onAssetEvidence={setAssetEvidence} onConfigureAssets={onConfigureAssets} snapshot={snapshot} catalog={catalog} focusObjectId={selectedFocusId} onFocus={setFocusObjectId} onPromote={setStatisticalScope} onProfile={()=>drill('profile')} onFlow={()=>drill('energyFlow')}/>}
     issues={<CockpitIssues key={"issues-"+snapshot.snapshotId} snapshot={snapshot} compact name={name} canEvidence={item=>!!cockpitIssueNavigation(snapshot,item,currentView())} onEvidence={item=>{const view=currentView(),navigation=cockpitIssueNavigation(snapshot,item,view);if(navigation)onDrill(navigation,snapshot,view);}}/>}/>
    <div className="cockpit-evidence-grid">
    {face!=='balance'&&snapshot.modules.balance&&<CockpitFlow key={"flow-"+snapshot.snapshotId} snapshot={snapshot} focusObjectId={selectedFocusId} compact onOpen={()=>drill('energyFlow')}/>}
    <section className="cockpit-trend" aria-labelledby="cockpit-trend-title"><h3 id="cockpit-trend-title">{t('用量趋势')}</h3>{report&&hasChart?<ReportChart snapshot={report} profileType="line" compact/>:<Empty description={t('此范围没有可绘制的有效时序数据')}/>}<p>{t('缺测与 NA 保留为空；已有用量不代表完整区间。')}</p></section>
    {presentationMode&&<CockpitNextSteps snapshot={snapshot}/>}
    </div>
    {snapshot.diagnostics&&<DiagnosticNotice metadata={snapshot.diagnostics} snapshotId={snapshot.snapshotId} objects={Object.fromEntries(catalog.records.filter(row=>row.id).map(row=>[row.id!,row.name]))}/>}
    <details className="cockpit-primary"><summary>{t('数据时刻与来源')}</summary>
     <p>{t('只读取所选设备的主能耗点历史。')}</p>
     <section className="cockpit-evidence" aria-label={t('数据时刻')}><dl><dt>{t('查询截止')}</dt><dd>{time(snapshot.context.asOf)}</dd><dt>{t('末次数据观察（非完整截止）')}</dt><dd>{time(snapshot.provenance.sourceLastObservedAt)}</dd><dt>{t('快照生成')}</dt><dd>{time(snapshot.generatedAt)}</dd></dl></section>
    </details>
    {(snapshot.limitations.length>0||snapshot.modules.kpis?.status!=='ok')&&<Alert showIcon type="warning" message={t('所选范围的数据或配置不完整，请展开查看来源与质量。')}/>}
    {report&&<details className="cockpit-details" id="cockpit-source-evidence"><summary>{t('查看趋势明细与数据来源')}</summary><div className="cockpit-table-scroll"><table><thead><tr><th>{t('对象')}</th><th>{t('时间')}</th><th>{t('已有用量')}</th><th>{t('完整区间用量')}</th><th>{t('单位')}</th><th>{t('数据质量')}</th></tr></thead><tbody>{report.result.series.flatMap(series=>series.points.map(point=><tr key={series.id+point.ts}><td>{series.name}</td><td>{time(point.ts)}</td><td>{point.knownValueType==='na'||point.knownValueType==null&&point.valueType==='na'?'NA':point.knownValue??point.value??'—'}</td><td>{cockpitCompleteValue(point)??'—'}</td><td>{series.unit}</td><td>{reportQualityText(report,point.quality)}</td></tr>))}</tbody></table></div><dl><dt>{t('主能耗点')}</dt><dd>{snapshot.boundary.sourcePointIds.join('、')||'—'}</dd><dt>{t('配置指纹')}</dt><dd>{snapshot.provenance.configFingerprint}</dd></dl><details><summary>{t('查看数据清洗依据')}</summary><dl><dt>{t('配置冻结观察区间')}</dt><dd>{time(snapshot.provenance.historyConfigObservedFrom)} — {time(snapshot.provenance.historyConfigObservedTo)}</dd><dt>{t('历史读取观察区间')}</dt><dd>{time(snapshot.provenance.historyObservedFrom)} — {time(snapshot.provenance.historyObservedTo)}</dd></dl><pre>{JSON.stringify(snapshot.provenance.appliedCleaning||report.result.extra?.cleaning||[],null,2)}</pre></details><ul>{snapshot.quality.map((q,index)=><li key={String(q.id||index)}>{String(q.name||q.nodeId||q.id||'—')}：{typeof q.coverage==='number'?new Intl.NumberFormat(locale,{style:'percent',maximumFractionDigits:1}).format(q.coverage):'—'}</li>)}</ul></details>}
   </section>}
  </>}
 </main>;
}
