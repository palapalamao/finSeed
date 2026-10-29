import {locale,t,type Locale} from './i18n';
import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {Alert,Button,ConfigProvider,Drawer,Empty,Layout,Space,Spin,Tabs,Tag} from 'antd';
import zhCN from 'antd/locale/zh_CN';
import enUS from 'antd/locale/en_US';
import {BarChartOutlined,BellOutlined,DashboardOutlined,FileTextOutlined,MenuOutlined,ReloadOutlined,SettingOutlined,UserOutlined} from '@ant-design/icons';
import {projectFromLocation,EnerCubixApi} from './api';
import {MessageCenter} from './MessageCenter';
import {Management,manageTitles,type ManageView} from './Management';
import {ReportWorkspace} from './ReportWorkspace';
import {analysisGroups} from './navigation';
import {BrandMark,productName,productTagline} from './brand';
import {type Catalog,type ReportKind,type ReportRequest} from './types';
import {version as uiVersion} from '../package.json';

const componentLocales:Record<Locale,typeof zhCN>={'zh-CN':zhCN,'en-US':enUS};
type View=ReportKind|ManageView|'messages';
const management:ManageView[]=['tree','categories','tariffs','calendars','expressions','copConfig','bindings','templates','tasks','settings','otherSettings'];
const settingsViews:ManageView[]=management.filter(key=>key!=='templates');
const reportViews:ReportKind[]=['dashboard','regression',...analysisGroups.flatMap(group=>group.kinds)];
function readTemplate(){return new URLSearchParams(location.hash.split('?')[1]||'').get('template')||undefined;}
function readView():View{const view=location.hash.slice(1).split('?')[0].replace(/^\//,'');if(view==='alarms')return 'messages';return [...reportViews,'messages',...management].includes(view as View)?view as View:'dashboard';}

export function App(){
 const[project,setProject]=useState(()=>projectFromLocation(location));
 const[view,setView]=useState<View>(readView);
 const[templateId,setTemplateId]=useState(readTemplate);
 const[catalog,setCatalog]=useState<Catalog|null>(null);
 const[loading,setLoading]=useState(true);
 const[error,setError]=useState('');
 const[mobileOpen,setMobileOpen]=useState(false);
 const api=useMemo(()=>project?new EnerCubixApi(project):null,[project]);
 const requestSequence=useRef(0);
 const lastAnalysis=useRef<ReportKind>('profile');
 const reload=useCallback(async()=>{if(!api)return;const sequence=++requestSequence.current;setLoading(true);try{const next=await api.catalog();if(sequence===requestSequence.current){setCatalog(next);setError('');}}catch(error){if(sequence===requestSequence.current)setError(error instanceof Error?error.message:t('无法读取项目配置'));}finally{if(sequence===requestSequence.current)setLoading(false);}},[api]);
 useEffect(()=>{setCatalog(null);void reload();return()=>{requestSequence.current++;};},[reload]);
 useEffect(()=>{const update=()=>{setView(readView());setTemplateId(readTemplate());setProject(projectFromLocation(location));};window.addEventListener('hashchange',update);return()=>window.removeEventListener('hashchange',update);},[]);
 const configView=management.includes(view as ManageView);
 const settingsView=settingsViews.includes(view as ManageView);
 const analysisView=!configView&&view!=='dashboard'&&view!=='messages';
 useEffect(()=>{if(analysisView)lastAnalysis.current=view as ReportKind;},[view,analysisView]);
 const navigate=(next:View,nextTemplate?:string)=>{setView(next);setTemplateId(nextTemplate);setMobileOpen(false);location.hash='/' + next + '?project=' + encodeURIComponent(project)+(nextTemplate?'&template='+encodeURIComponent(nextTemplate):'');};
 const version=uiVersion;
 const versionMismatch=!!catalog?.version&&catalog.version!==uiVersion;
 const destinations=[
  {key:'dashboard',label:t('总览'),icon:<DashboardOutlined/>,target:'dashboard' as View},
  {key:'analysis',label:t('分析工作台'),icon:<BarChartOutlined/>,target:(analysisView?view:lastAnalysis.current) as View},
  {key:'templates',label:t('报告模板'),icon:<FileTextOutlined/>,target:'templates' as View},
  {key:'messages',label:t('消息中心'),icon:<BellOutlined/>,target:'messages' as View},
  {key:'configuration',label:t('设置'),icon:<SettingOutlined/>,target:'tree' as View}
 ];
 const selectedDestination=analysisView?'analysis':settingsView?'configuration':view;
 const navigation=(mobile=false)=><nav className={mobile?'mobile-navigation':'primary-navigation'} aria-label={t('主导航')}>{destinations.map(item=><Button key={item.key} type="text" aria-label={item.label} icon={mobile?item.icon:undefined} aria-current={selectedDestination===item.key?'page':undefined} className={selectedDestination===item.key?'nav-active':undefined} onClick={()=>navigate(item.target)}>{item.label}</Button>)}</nav>;
 return <ConfigProvider locale={componentLocales[locale]} theme={{token:{colorPrimary:'#137f7a',colorSuccess:'#218374',colorInfo:'#3976ba',colorBgLayout:'#f3f6f8',colorText:'#24323d',borderRadius:6,fontFamily:'"Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", sans-serif',fontSize:13,controlHeight:34},components:{Table:{headerBg:'#f3f6f8'},Layout:{headerBg:'#fff'}}}}>
  <Layout className="app-layout enercubix-app">
   <Layout.Header className="app-header">
    <Button type="text" className="mobile-nav-toggle" icon={<MenuOutlined/>} aria-label={t('打开导航')} onClick={()=>setMobileOpen(true)}/>
    <a className="brand-wordmark" href={'#/dashboard?project='+encodeURIComponent(project)} aria-label={productName}><BrandMark/><span><strong>{productName}</strong><small>{productTagline}</small></span></a>
    {navigation()}
    <Space className="header-tools" size={8}>
     <span className="project-context" title={project}>{project||t('未指定项目')}</span>
     <Tag className="access-tag" color={catalog?.user.canWrite?'cyan':'default'}>{catalog?.user.canWrite?t('项目管理'):t('只读访问')}</Tag>
     <span className="user-context"><UserOutlined/><span>{catalog?.user.name||t('FIN 用户')}</span></span>
     <Button type="text" icon={<ReloadOutlined/>} aria-label={t('刷新项目')} loading={loading} onClick={()=>void reload()}/>
    </Space>
   </Layout.Header>
   <Drawer aria-label={t('主导航')} title={t('主导航')} placement="left" width={280} open={mobileOpen} onClose={()=>setMobileOpen(false)}><div className="mobile-project-context"><strong>{project||t('未指定项目')}</strong><span>{catalog?.user.name||t('FIN 用户')}</span><Tag>{catalog?.user.canWrite?t('项目管理'):t('只读访问')}</Tag></div>{navigation(true)}<div className="mobile-nav-version">{productName} · v{version}</div></Drawer>
   <Layout.Content className="app-content">
    {!project?<div className="connection-state"><Empty description={t('尚未指定 FIN 项目')}/><Alert type="info" showIcon message={t('请从 FIN 项目打开能源管理，或在地址中指定 #/dashboard?project=项目名。')}/></div>:!catalog?<div className="connection-state">{loading?<Spin tip={t('正在读取 FIN 项目配置…')}/>:<><Alert type="error" showIcon message={error||t('项目配置尚未加载')}/><Button onClick={()=>void reload()}>{t('重新连接')}</Button></>}</div>:<>
     {error&&<Alert banner type="error" message={error}/>}
     {versionMismatch&&<Alert banner type="warning" showIcon message={t('当前界面版本为 {0}，服务版本为 {1}。请重新打开能源魔方以加载最新界面。',uiVersion,catalog.version)} action={<Button onClick={()=>location.assign(`/api/${encodeURIComponent(project)}/ext/enerCubix/`)}>{t('加载新版界面')}</Button>}/>}
     <div className="content-frame">
      {settingsView&&<div className="settings-navigation"><Tabs activeKey={view} onChange={key=>navigate(key as View)} items={settingsViews.map(key=>({key,label:key==='tree'?t('计量资产'):manageTitles[key]}))}/></div>}
      {view==='messages'?<MessageCenter api={api!} canWrite={catalog.user.canWrite} records={catalog.records}/>:configView?<Management key={view} view={view as ManageView} api={api!} catalog={catalog} reload={reload} onOpenTemplate={record=>{const request=record.request as ReportRequest;if(request&&reportViews.includes(request.kind))navigate(request.kind,record.id);}}/>:<ReportWorkspace key={project} initialTemplateId={templateId} kind={view as ReportKind} api={api!} catalog={catalog} reload={reload} navigate={navigate}/>}
     </div>
    </>}
   </Layout.Content>
   <Layout.Footer className="app-footer"><span>{productName} · <span className="nav-version" aria-label={t('当前版本')}>v{version}</span></span><span>{t('数据、权限与历史由 FIN 项目提供')}</span></Layout.Footer>
  </Layout>
 </ConfigProvider>;
}
