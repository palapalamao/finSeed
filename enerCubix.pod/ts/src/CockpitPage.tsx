import {useEffect,useMemo,useRef,useState,useSyncExternalStore} from 'react';
import {Alert,Button,Empty,Select,Spin,Tag} from 'antd';
import type {EnerCubixApi} from './api';
import type {Catalog} from './types';
import {cockpitModules,type CockpitFace,type CockpitRequest,type CockpitScope} from './cockpitTypes';
import {CockpitQuery,defaultCockpitSelection} from './cockpitQuery';
import {dimensionRecords} from './dimensionTree';
import {ReportChart} from './ReportView';
import {locale,t} from './i18n';
import {reportQualityText} from './reportQuality';
import {cockpitProfileSnapshot,cockpitCompleteValue} from './cockpitReport';
import {absoluteCockpitRequest,createFaceNavigation,createNavigation,type CockpitTargetKind,focusRecords,focusPath,type CockpitReturnState,type CockpitViewState,type NavigationContextV1} from './cockpitNavigation';
import {CockpitKpis} from './CockpitKpis';
import {CockpitDates,type CockpitDateDraft} from './CockpitDates';
import {cockpitAuxiliaryCategory} from './cockpitMetrics';
import {CockpitMain} from './CockpitMain';
import {CockpitFlow} from './CockpitFlow';
import {cockpitCopNavigation} from './cockpitEfficiencyProjection';
import {CockpitIssues} from './CockpitIssues';
import {cockpitIssueNavigation} from './cockpitIssueProjection';
import './cockpit.css';

// Keep the legacy dashboard route available throughout incremental delivery.
export const cockpitEnabled=true;
function time(value:string|null|undefined){return value?value.replace('T',' '):t('暂无数据');}
export function CockpitPage({api,catalog,onLegacy,onConfigure,initialRequest,restored,initialView,onDrill,onSnapshot}:{initialView?:{focusObjectId?:string;selectedFace:CockpitFace;presentationMode:boolean;scrollY:number};onSnapshot?:(snapshot:import('./cockpitTypes').CockpitSnapshot,view:CockpitViewState)=>void;initialRequest?:CockpitRequest;restored?:CockpitReturnState;onDrill:(navigation:NavigationContextV1,snapshot:import('./cockpitTypes').CockpitSnapshot,view:CockpitViewState)=>void;api:EnerCubixApi;catalog:Catalog;onLegacy:()=>void;onConfigure:()=>void}){
 const selection=useMemo(()=>defaultCockpitSelection(catalog),[catalog]);
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
 const query=useMemo(()=>new CockpitQuery((request,signal)=>api.cockpit(request,signal)),[api]);
 const state=useSyncExternalStore(query.subscribe,query.getSnapshot,query.getSnapshot);
 const makeRequest=():CockpitRequest|undefined=>{const previous=state.snapshot?.context||initialRequest;const keepCutoff=preset==='custom'&&previous&&Date.parse(dates.from||'')===Date.parse(previous.time.from||'')&&Date.parse(dates.to||'')===Date.parse(previous.time.to||'');return selection&&scope&&categoryId?{schemaVersion:1,requestId:'cockpit-'+(++sequence.current),reportScope:scope,focusCategoryId:categoryId,...(auxiliaryCategoryId?{auxiliaryCategoryId}:{}),time:preset==='custom'?{preset,period:dates.period,from:dates.from,to:dates.to}:{preset,period:preset==='today'?'hour':preset==='thisYear'?'month':'day'},...(keepCutoff?{asOf:previous.asOf}:{}),comparison:dates.comparison.mode==='custom'?dates.comparison:{mode:dates.comparison.mode},modules:[...cockpitModules]}:undefined;};
 const apply=()=>{const request=makeRequest();if(request)void query.apply(request);};
 useEffect(()=>{if(restored){query.restore(restored.snapshot);requestAnimationFrame(()=>window.scrollTo(0,restored.view.scrollY));}else if(initialRequest){void query.apply({...initialRequest,requestId:'restore-'+(++sequence.current)});}else if(selection&&query.getSnapshot().phase==='idle'){void query.apply({schemaVersion:1,requestId:'initial-'+(++sequence.current),reportScope:selection.scope,focusCategoryId:selection.categoryId,...(auxiliaryCategoryId?{auxiliaryCategoryId}:{}),time:{preset:'thisMonth',period:'day'},comparison:{mode:'presetDefault'},modules:[...cockpitModules]});}return()=>query.cancel();},[query]);
 const snapshot=state.snapshot,report=useMemo(()=>snapshot?cockpitProfileSnapshot(snapshot):undefined,[snapshot]);
 useEffect(()=>{if(snapshot)setDates(current=>current.from&&current.to?current:{...current,from:snapshot.context.time.from,to:snapshot.context.time.to});},[snapshot]);
 const dateInvalid=preset==='custom'&&(!dates.from||!dates.to||Date.parse(dates.from)>=Date.parse(dates.to))||dates.comparison.mode==='custom'&&(!dates.comparison.from||!dates.comparison.to||Date.parse(dates.comparison.from)>=Date.parse(dates.comparison.to));
 const loading=state.phase==='loading'||state.phase==='refreshing';
 const scopeRows=dimensionRecords(catalog.records,scope?.dimension||'space',catalog.spaceSource==='fin').filter(r=>r.id&&!r.nativeHidden&&['space','organization','meter','totalMeter'].includes(r.kind));
 const categories=catalog.records.filter(r=>r.kind==='category'&&r.id);
 const sameComparison=!!snapshot&&(dates.comparison.mode===(snapshot.context.comparison?.mode||'none')&&(dates.comparison.mode!=='custom'||Date.parse(dates.comparison.from||'')===Date.parse(snapshot.context.comparison?.from||'')&&Date.parse(dates.comparison.to||'')===Date.parse(snapshot.context.comparison?.to||'')));
 const dirty=!!snapshot&&(scope?.dimension!==snapshot.context.reportScope.dimension||scope?.selectionIntent!==snapshot.context.reportScope.selectionIntent||JSON.stringify(scope?.nodeIds)!==JSON.stringify(snapshot.context.reportScope.nodeIds)||categoryId!==snapshot.context.focusCategoryId||auxiliaryCategoryId!==(snapshot.context.auxiliaryCategoryId??undefined)||preset!==snapshot.context.time.preset||!sameComparison||preset==='custom'&&(Date.parse(dates.from||'')!==Date.parse(snapshot.context.time.from)||Date.parse(dates.to||'')!==Date.parse(snapshot.context.time.to)||dates.period!==snapshot.context.time.period));
 const name=(id:string)=>catalog.records.find(r=>r.id===id)?.name||id;
 const hasChart=report?.result.series.some(series=>series.points.some(point=>point.value!==null||point.knownValue!=null));
 const focusRows=snapshot&&snapshot.capabilities.canRead?focusRecords(catalog,snapshot.context.reportScope):[];
 const focused=focusRows.find(r=>r.id===focusObjectId);
 const currentView=():CockpitViewState=>({focusObjectId:focused?.id,selectedFace:face,presentationMode,scrollY:window.scrollY,draft:{scope:scope!,categoryId:categoryId!,preset,auxiliarySelection:auxiliarySelection||auxiliaryCategoryId||'__area__',dates}});
 const drill=(kind:'profile'|'energyFlow')=>{if(!snapshot)return;const view=currentView();onDrill(createNavigation(snapshot,kind,view),snapshot,view);};
 const drillFace=(kind:Exclude<CockpitTargetKind,'energyFlow'>)=>{if(!snapshot)return;const view=currentView();onDrill(createFaceNavigation(snapshot,kind,view),snapshot,view);};
 useEffect(()=>{if(snapshot&&scope&&categoryId)onSnapshot?.(snapshot,currentView());},[snapshot,face,focused?.id,presentationMode]);
 const setStatisticalScope=()=>{if(!focused?.id||!snapshot)return;const next:CockpitScope={dimension:snapshot.context.reportScope.dimension,nodeIds:[focused.id],selectionIntent:['meter','totalMeter'].includes(focused.kind)?'explicitObjects':'range'};const applied=absoluteCockpitRequest(snapshot);setScope(next);setFocusObjectId(undefined);setCategoryId(applied.focusCategoryId);setAuxiliarySelection(applied.auxiliaryCategoryId||'__area__');setPreset('custom');setDates({from:applied.time.from,to:applied.time.to,period:applied.time.period,comparison:applied.comparison||{mode:'none'}});void query.apply({...applied,requestId:'scope-'+(++sequence.current),reportScope:next});};
 return <main className={presentationMode?"cockpit-page cockpit-presentation":"cockpit-page"} aria-labelledby="cockpit-title">
  <header className="cockpit-heading"><div><h2 id="cockpit-title">{t('能源经营驾驶舱')}</h2><p>{t('从真实用量开始，定位范围并核对数据依据。')}</p></div><Button onClick={onLegacy}>{t('旧版总览')}</Button></header>
  {!selection?<section className="cockpit-empty"><Empty description={t('尚无可分析的主能耗点配置')}/><p>{t('请先选择设备、绑定主能耗点并配置能源分类。')}</p>{catalog.user.canWrite?<Button onClick={onConfigure}>{t('配置计量资产')}</Button>:<p>{t('请联系项目管理员完善配置。')}</p>}</section>:<>
   <section className="cockpit-controls" aria-label={t('驾驶舱查询条件')}>
    <label>{t('统计范围')}<Select aria-label={t('统计范围')} mode="multiple" value={scope?.nodeIds} onChange={nodeIds=>setScope(current=>({...current!,nodeIds}))} options={scopeRows.map(r=>({value:r.id,label:r.name}))}/></label>
    <label>{t('范围选择方式')}<Select aria-label={t('范围选择方式')} value={scope?.selectionIntent} onChange={selectionIntent=>setScope(current=>({...current!,selectionIntent}))} options={[{value:'range',label:t('范围')},{value:'explicitObjects',label:t('明确对象')}]}/></label>
    <label>{t('关注能源')}<Select aria-label={t('关注能源')} value={categoryId} onChange={value=>{setCategoryId(value);setAuxiliarySelection(undefined);}} options={categories.map(r=>({value:r.id,label:r.name}))}/></label>
    <label>{t('统计时间')}<Select aria-label={t('统计时间')} value={preset} onChange={setPreset} options={[{value:'today',label:t('今日')},{value:'thisMonth',label:t('本月')},{value:'thisYear',label:t('本年')},{value:'custom',label:t('自定义时间')}]}/></label>
    <label>{t('辅助能源')}<Select aria-label={t('辅助能源')} value={auxiliaryCategoryId||'__area__'} onChange={setAuxiliarySelection} options={[{value:'__area__',label:t('单位面积用量')},...categories.filter(category=>category.id!==categoryId&&catalog.records.some(meter=>['meter','totalMeter'].includes(meter.kind)&&meter.pointId&&meter.categoryId===category.id)).map(category=>({value:category.id!,label:category.name}))]}/></label>
    <CockpitDates preset={preset} draft={dates} onChange={setDates}/>
    <Button type="primary" disabled={state.phase==='sessionExpired'||!scope?.nodeIds.length||!!dateInvalid} onClick={apply}>{dirty?t('应用条件'):t('刷新数据')}</Button>
    {dirty&&<Tag>{t('条件尚未应用')}</Tag>}
   </section>
   <div aria-live="polite">{loading&&<p className="cockpit-loading"><Spin size="small"/> {t('正在读取驾驶舱数据…')}</p>}{state.error&&<Alert type="error" showIcon message={state.error}/>}</div>
   {snapshot&&<section className="cockpit-snapshot" aria-label={t('驾驶舱数据快照')}>
    {(state.phase!=='ready'||dirty)&&<Alert type="info" showIcon message={t('当前保留上次成功快照，范围和时间以此处标注为准。')}/>}
    {initialRequest&&!restored&&<Alert type="info" showIcon message={t('已恢复绝对查询条件并重新读取，这是新快照。')}/>}
    {restored?.configurationChanged&&<Alert type="warning" showIcon message={t('当前配置已变化；此处保留原快照，重新查询将使用当前配置。')}/>}
    <div className="cockpit-context"><strong>{snapshot.context.reportScope.nodeIds.map(name).join('、')} / {name(snapshot.context.focusCategoryId)}</strong><p>{time(snapshot.context.time.from)} — {time(snapshot.context.time.to)} {t('（结束时间不含）')}</p><p>{t('项目时区：{0}',snapshot.context.projectTimeZone)}</p></div>
    <CockpitKpis snapshot={snapshot} name={name}/>
    <CockpitIssues key={snapshot.snapshotId} snapshot={snapshot} name={name} canEvidence={item=>!!cockpitIssueNavigation(snapshot,item,currentView())} onEvidence={item=>{const view=currentView(),navigation=cockpitIssueNavigation(snapshot,item,view);if(navigation)onDrill(navigation,snapshot,view);}}/>
    <CockpitMain snapshot={snapshot} face={face} onFace={setFace} onReport={drillFace} name={name} focusObjectId={focused?.id} onFlow={()=>drill('energyFlow')} onCop={id=>{const view=currentView();onDrill(cockpitCopNavigation(snapshot,id,view),snapshot,view);}}/>
    {face==='space'&&<section className="cockpit-focus-section" aria-label={t('真实空间与对象')}><div><h3>{t('真实空间与对象')}</h3><p>{t('选择焦点仅查看配置，不改变统计范围或全局用量。')}</p><ul className="cockpit-object-list">{focusRows.map(row=><li key={row.id}><button type="button" aria-pressed={focused?.id===row.id} onClick={()=>setFocusObjectId(row.id)}>{focusPath(catalog,row.id!,snapshot.context.reportScope)}</button></li>)}</ul></div><section className="cockpit-focus-panel" aria-label={t('焦点详情')}><h3>{t('焦点详情')}</h3>{focused?<><strong>{focused.name}</strong><dl><dt>{t('对象类型')}</dt><dd>{t(({site:'站点',floor:'楼层',equip:'设备'} as Record<string,string>)[String(focused.nativeSourceKind||focused.nativeLevel)]||'对象')}</dd><dt>{t('主能耗点')}</dt><dd>{String(focused.pointId||t('未配置'))}</dd><dt>{t('对象用量')}</dt><dd>{t('当前快照未加载此对象用量')}</dd></dl><Button onClick={setStatisticalScope}>{t('设为统计范围')}</Button><Button onClick={()=>setFocusObjectId(undefined)}>{t('清除焦点')}</Button></>:<p>{t('请选择范围内的对象')}</p>}<div className="cockpit-drill-actions"><Button onClick={()=>drill('profile')}>{t('打开专业趋势')}</Button><Button onClick={()=>drill('energyFlow')}>{t('打开完整能流')}</Button><Button onClick={()=>setPresentationMode(value=>!value)}>{presentationMode?t('退出汇报布局'):t('汇报布局')}</Button></div></section></section>}
    <div className="cockpit-primary">
     <p>{t('只读取所选设备的主能耗点历史。')}</p>
     <section className="cockpit-evidence" aria-label={t('数据时刻')}><dl><dt>{t('查询截止')}</dt><dd>{time(snapshot.context.asOf)}</dd><dt>{t('末次数据观察（非完整截止）')}</dt><dd>{time(snapshot.provenance.sourceLastObservedAt)}</dd><dt>{t('快照生成')}</dt><dd>{time(snapshot.generatedAt)}</dd></dl></section>
    </div>
    {(snapshot.limitations.length>0||snapshot.modules.kpis?.status!=='ok')&&<Alert showIcon type="warning" message={t('所选范围的数据或配置不完整，请展开查看来源与质量。')}/>}
    {face!=='balance'&&snapshot.modules.balance&&<CockpitFlow key={snapshot.snapshotId} snapshot={snapshot} focusObjectId={focused?.id} compact onOpen={()=>drill('energyFlow')}/>}
    <section className="cockpit-trend" aria-labelledby="cockpit-trend-title"><h3 id="cockpit-trend-title">{t('用量趋势')}</h3><p>{t('缺测与 NA 保留为空；已有用量不代表完整区间。')}</p>{report&&hasChart?<ReportChart snapshot={report} profileType="line"/>:<Empty description={t('此范围没有可绘制的有效时序数据')}/>}</section>
    {report&&<details className="cockpit-details"><summary>{t('查看趋势明细与数据来源')}</summary><div className="cockpit-table-scroll"><table><thead><tr><th>{t('对象')}</th><th>{t('时间')}</th><th>{t('已有用量')}</th><th>{t('完整区间用量')}</th><th>{t('单位')}</th><th>{t('数据质量')}</th></tr></thead><tbody>{report.result.series.flatMap(series=>series.points.map(point=><tr key={series.id+point.ts}><td>{series.name}</td><td>{time(point.ts)}</td><td>{point.knownValueType==='na'||point.knownValueType==null&&point.valueType==='na'?'NA':point.knownValue??point.value??'—'}</td><td>{cockpitCompleteValue(point)??'—'}</td><td>{series.unit}</td><td>{reportQualityText(report,point.quality)}</td></tr>))}</tbody></table></div><dl><dt>{t('主能耗点')}</dt><dd>{snapshot.boundary.sourcePointIds.join('、')||'—'}</dd><dt>{t('配置指纹')}</dt><dd>{snapshot.provenance.configFingerprint}</dd></dl><details><summary>{t('查看数据清洗依据')}</summary><dl><dt>{t('配置冻结观察区间')}</dt><dd>{time(snapshot.provenance.historyConfigObservedFrom)} — {time(snapshot.provenance.historyConfigObservedTo)}</dd><dt>{t('历史读取观察区间')}</dt><dd>{time(snapshot.provenance.historyObservedFrom)} — {time(snapshot.provenance.historyObservedTo)}</dd></dl><pre>{JSON.stringify(snapshot.provenance.appliedCleaning||report.result.extra?.cleaning||[],null,2)}</pre></details><ul>{snapshot.quality.map((q,index)=><li key={String(q.id||index)}>{String(q.name||q.nodeId||q.id||'—')}：{typeof q.coverage==='number'?new Intl.NumberFormat(locale,{style:'percent',maximumFractionDigits:1}).format(q.coverage):'—'}</li>)}</ul></details>}
   </section>}
  </>}
 </main>;
}
