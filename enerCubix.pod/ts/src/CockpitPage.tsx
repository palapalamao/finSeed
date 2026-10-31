import {useEffect,useMemo,useRef,useState,useSyncExternalStore} from 'react';
import {Alert,Button,Empty,Select,Spin,Tag} from 'antd';
import type {EnerCubixApi} from './api';
import type {Catalog} from './types';
import type {CockpitRequest,CockpitScope} from './cockpitTypes';
import {CockpitQuery,defaultCockpitSelection} from './cockpitQuery';
import {dimensionRecords} from './dimensionTree';
import {ReportChart} from './ReportView';
import {locale,t} from './i18n';
import {reportQualityText} from './reportQuality';
import {cockpitProfileSnapshot,cockpitCompleteValue} from './cockpitReport';
import {createNavigation,focusRecords,focusPath,type CockpitReturnState,type CockpitViewState,type NavigationContextV1} from './cockpitNavigation';
import './cockpit.css';

// Keep the legacy dashboard route available throughout incremental delivery.
export const cockpitEnabled=true;
function time(value:string|null|undefined){return value?value.replace('T',' '):t('暂无数据');}
export function CockpitPage({api,catalog,onLegacy,onConfigure,initialRequest,restored,onDrill,onSnapshot}:{onSnapshot?:(snapshot:import('./cockpitTypes').CockpitSnapshot,view:CockpitViewState)=>void;initialRequest?:CockpitRequest;restored?:CockpitReturnState;onDrill:(navigation:NavigationContextV1,snapshot:import('./cockpitTypes').CockpitSnapshot,view:CockpitViewState)=>void;api:EnerCubixApi;catalog:Catalog;onLegacy:()=>void;onConfigure:()=>void}){
 const selection=useMemo(()=>defaultCockpitSelection(catalog),[catalog]);
 const [scope,setScope]=useState<CockpitScope|undefined>(()=>restored?.view.draft.scope||initialRequest?.reportScope||selection?.scope);
 const [focusObjectId,setFocusObjectId]=useState(restored?.view.focusObjectId);
 const [presentationMode,setPresentationMode]=useState(restored?.view.presentationMode||false);
 const [categoryId,setCategoryId]=useState(restored?.view.draft.categoryId||initialRequest?.focusCategoryId||selection?.categoryId);
 const [preset,setPreset]=useState<CockpitRequest['time']['preset']>(restored?.view.draft.preset||initialRequest?.time.preset||'thisMonth');
 const sequence=useRef(0);
 const query=useMemo(()=>new CockpitQuery((request,signal)=>api.cockpit(request,signal)),[api]);
 const state=useSyncExternalStore(query.subscribe,query.getSnapshot,query.getSnapshot);
 const makeRequest=():CockpitRequest|undefined=>selection&&scope&&categoryId?{schemaVersion:1,requestId:'cockpit-'+(++sequence.current),reportScope:scope,focusCategoryId:categoryId,...(initialRequest?.auxiliaryCategoryId?{auxiliaryCategoryId:initialRequest.auxiliaryCategoryId}:{}),time:preset==='custom'&&initialRequest?initialRequest.time:{preset,period:preset==='today'?'hour':preset==='thisYear'?'month':'day'},comparison:{mode:'none'},modules:['kpis','trend']}:undefined;
 const apply=()=>{const request=makeRequest();if(request)void query.apply(request);};
 useEffect(()=>{if(restored){query.restore(restored.snapshot);requestAnimationFrame(()=>window.scrollTo(0,restored.view.scrollY));}else if(initialRequest){void query.apply({...initialRequest,requestId:'restore-'+(++sequence.current)});}else if(selection&&query.getSnapshot().phase==='idle'){void query.apply({schemaVersion:1,requestId:'initial-'+(++sequence.current),reportScope:selection.scope,focusCategoryId:selection.categoryId,time:{preset:'thisMonth',period:'day'},comparison:{mode:'none'},modules:['kpis','trend']});}return()=>query.cancel();},[query]);
 const snapshot=state.snapshot,report=useMemo(()=>snapshot?cockpitProfileSnapshot(snapshot):undefined,[snapshot]);
 const metric=snapshot?.modules.kpis?.data?.values.find(value=>value.id==='energy');
 const loading=state.phase==='loading'||state.phase==='refreshing';
 const scopeRows=dimensionRecords(catalog.records,scope?.dimension||'space',catalog.spaceSource==='fin').filter(r=>r.id&&!r.nativeHidden&&['space','organization','meter','totalMeter'].includes(r.kind));
 const categories=catalog.records.filter(r=>r.kind==='category'&&r.id);
 const dirty=!!snapshot&&(JSON.stringify(scope)!==JSON.stringify(snapshot.context.reportScope)||categoryId!==snapshot.context.focusCategoryId||preset!==snapshot.context.time.preset);
 const name=(id:string)=>catalog.records.find(r=>r.id===id)?.name||id;
 const hasChart=report?.result.series.some(series=>series.points.some(point=>point.value!==null||point.knownValue!=null));
 const status=metric?.valueBasis==='complete'?t('完整区间用量'):metric?.valueBasis==='cleanedWithReplacement'?t('清洗后用量，含替代值'):metric?.valueBasis==='knownSubtotal'?t('有效用量小计'):t('暂无有效用量');
 const focusRows=snapshot&&snapshot.capabilities.canRead?focusRecords(catalog,snapshot.context.reportScope):[];
 const focused=focusRows.find(r=>r.id===focusObjectId);
 const drill=(kind:'profile'|'energyFlow')=>{if(!snapshot)return;const view:CockpitViewState={focusObjectId:focused?.id,selectedFace:'space',presentationMode,scrollY:window.scrollY,draft:{scope:scope!,categoryId:categoryId!,preset}};onDrill(createNavigation(snapshot,kind,view),snapshot,view);};
 useEffect(()=>{if(snapshot&&scope&&categoryId)onSnapshot?.(snapshot,{focusObjectId:focused?.id,selectedFace:'space',presentationMode,scrollY:window.scrollY,draft:{scope,categoryId,preset}});},[snapshot]);
 const setStatisticalScope=()=>{if(!focused?.id||!snapshot)return;const next:CockpitScope={dimension:snapshot.context.reportScope.dimension,nodeIds:[focused.id],selectionIntent:['meter','totalMeter'].includes(focused.kind)?'explicitObjects':'range'};setScope(next);setFocusObjectId(undefined);void query.apply({...makeRequest()!,reportScope:next});};
 return <main className={presentationMode?"cockpit-page cockpit-presentation":"cockpit-page"} aria-labelledby="cockpit-title">
  <header className="cockpit-heading"><div><h2 id="cockpit-title">{t('能源经营驾驶舱')}</h2><p>{t('从真实用量开始，定位范围并核对数据依据。')}</p></div><Button onClick={onLegacy}>{t('旧版总览')}</Button></header>
  {!selection?<section className="cockpit-empty"><Empty description={t('尚无可分析的主能耗点配置')}/><p>{t('请先选择设备、绑定主能耗点并配置能源分类。')}</p>{catalog.user.canWrite?<Button onClick={onConfigure}>{t('配置计量资产')}</Button>:<p>{t('请联系项目管理员完善配置。')}</p>}</section>:<>
   <section className="cockpit-controls" aria-label={t('驾驶舱查询条件')}>
    <label>{t('统计范围')}<Select aria-label={t('统计范围')} mode="multiple" value={scope?.nodeIds} onChange={nodeIds=>setScope(current=>({...current!,nodeIds}))} options={scopeRows.map(r=>({value:r.id,label:r.name}))}/></label>
    <label>{t('范围选择方式')}<Select aria-label={t('范围选择方式')} value={scope?.selectionIntent} onChange={selectionIntent=>setScope(current=>({...current!,selectionIntent}))} options={[{value:'range',label:t('范围')},{value:'explicitObjects',label:t('明确对象')}]}/></label>
    <label>{t('关注能源')}<Select aria-label={t('关注能源')} value={categoryId} onChange={setCategoryId} options={categories.map(r=>({value:r.id,label:r.name}))}/></label>
    <label>{t('统计时间')}<Select aria-label={t('统计时间')} value={preset} onChange={setPreset} options={[...(preset==='custom'?[{value:'custom',label:t('固定绝对区间')}]:[]),{value:'today',label:t('今日')},{value:'thisMonth',label:t('本月')},{value:'thisYear',label:t('本年')}]}/></label>
    <Button type="primary" disabled={state.phase==='sessionExpired'||!scope?.nodeIds.length} onClick={apply}>{dirty?t('应用条件'):t('刷新数据')}</Button>
    {dirty&&<Tag>{t('条件尚未应用')}</Tag>}
   </section>
   <div aria-live="polite">{loading&&<p className="cockpit-loading"><Spin size="small"/> {t('正在读取驾驶舱数据…')}</p>}{state.error&&<Alert type="error" showIcon message={state.error}/>}</div>
   {snapshot&&<section className="cockpit-snapshot" aria-label={t('驾驶舱数据快照')}>
    {(state.phase!=='ready'||dirty)&&<Alert type="info" showIcon message={t('当前保留上次成功快照，范围和时间以此处标注为准。')}/>}
    {initialRequest&&!restored&&<Alert type="info" showIcon message={t('已恢复绝对查询条件并重新读取，这是新快照。')}/>}
    {restored?.configurationChanged&&<Alert type="warning" showIcon message={t('当前配置已变化；此处保留原快照，重新查询将使用当前配置。')}/>}
    <div className="cockpit-context"><strong>{snapshot.context.reportScope.nodeIds.map(name).join('、')} / {name(snapshot.context.focusCategoryId)}</strong><p>{time(snapshot.context.time.from)} — {time(snapshot.context.time.to)} {t('（结束时间不含）')}</p><p>{t('项目时区：{0}',snapshot.context.projectTimeZone)}</p></div>
    <section className="cockpit-focus-section" aria-label={t('真实空间与对象')}><div><h3>{t('真实空间与对象')}</h3><p>{t('选择焦点仅查看配置，不改变统计范围或全局用量。')}</p><ul className="cockpit-object-list">{focusRows.map(row=><li key={row.id}><button type="button" aria-pressed={focused?.id===row.id} onClick={()=>setFocusObjectId(row.id)}>{focusPath(catalog,row.id!,snapshot.context.reportScope)}</button></li>)}</ul></div><section className="cockpit-focus-panel" aria-label={t('焦点详情')}><h3>{t('焦点详情')}</h3>{focused?<><strong>{focused.name}</strong><dl><dt>{t('对象类型')}</dt><dd>{t(({site:'站点',floor:'楼层',equip:'设备'} as Record<string,string>)[String(focused.nativeSourceKind||focused.nativeLevel)]||'对象')}</dd><dt>{t('主能耗点')}</dt><dd>{String(focused.pointId||t('未配置'))}</dd><dt>{t('对象用量')}</dt><dd>{t('当前快照未加载此对象用量')}</dd></dl><Button onClick={setStatisticalScope}>{t('设为统计范围')}</Button><Button onClick={()=>setFocusObjectId(undefined)}>{t('清除焦点')}</Button></>:<p>{t('请选择范围内的对象')}</p>}<div className="cockpit-drill-actions"><Button onClick={()=>drill('profile')}>{t('打开专业趋势')}</Button><Button onClick={()=>drill('energyFlow')}>{t('打开完整能流')}</Button><Button onClick={()=>setPresentationMode(value=>!value)}>{presentationMode?t('退出汇报布局'):t('汇报布局')}</Button></div></section></section>
    <div className="cockpit-primary">
     <section className="cockpit-energy" aria-label={t('关注能源用量')}><h3>{t('关注能源用量')}</h3><p className="cockpit-number">{metric?.valueType==='na'?'NA':metric?.value!=null?new Intl.NumberFormat(locale,{maximumFractionDigits:3}).format(metric.value):'—'} <small>{metric?.unit||''}</small></p><Tag color={metric?.valueBasis==='complete'?'green':'gold'}>{status}</Tag><p>{t('只读取所选设备的主能耗点历史。')}</p></section>
     <section className="cockpit-evidence" aria-label={t('数据时刻')}><dl><dt>{t('查询截止')}</dt><dd>{time(snapshot.context.asOf)}</dd><dt>{t('末次数据观察（非完整截止）')}</dt><dd>{time(snapshot.provenance.sourceLastObservedAt)}</dd><dt>{t('快照生成')}</dt><dd>{time(snapshot.generatedAt)}</dd></dl></section>
    </div>
    {(snapshot.limitations.length>0||snapshot.modules.kpis?.status!=='ok')&&<Alert showIcon type="warning" message={t('所选范围的数据或配置不完整，请展开查看来源与质量。')}/>}
    <section className="cockpit-trend" aria-labelledby="cockpit-trend-title"><h3 id="cockpit-trend-title">{t('用量趋势')}</h3><p>{t('缺测与 NA 保留为空；已有用量不代表完整区间。')}</p>{report&&hasChart?<ReportChart snapshot={report} profileType="line"/>:<Empty description={t('此范围没有可绘制的有效时序数据')}/>}</section>
    {report&&<details className="cockpit-details"><summary>{t('查看趋势明细与数据来源')}</summary><div className="cockpit-table-scroll"><table><thead><tr><th>{t('对象')}</th><th>{t('时间')}</th><th>{t('已有用量')}</th><th>{t('完整区间用量')}</th><th>{t('单位')}</th><th>{t('数据质量')}</th></tr></thead><tbody>{report.result.series.flatMap(series=>series.points.map(point=><tr key={series.id+point.ts}><td>{series.name}</td><td>{time(point.ts)}</td><td>{point.knownValueType==='na'||point.knownValueType==null&&point.valueType==='na'?'NA':point.knownValue??point.value??'—'}</td><td>{cockpitCompleteValue(point)??'—'}</td><td>{series.unit}</td><td>{reportQualityText(report,point.quality)}</td></tr>))}</tbody></table></div><dl><dt>{t('主能耗点')}</dt><dd>{snapshot.boundary.sourcePointIds.join('、')||'—'}</dd><dt>{t('配置指纹')}</dt><dd>{snapshot.provenance.configFingerprint}</dd></dl><ul>{snapshot.quality.map((q,index)=><li key={String(q.id||index)}>{String(q.name||q.nodeId||q.id||'—')}：{typeof q.coverage==='number'?new Intl.NumberFormat(locale,{style:'percent',maximumFractionDigits:1}).format(q.coverage):'—'}</li>)}</ul></details>}
   </section>}
  </>}
 </main>;
}
