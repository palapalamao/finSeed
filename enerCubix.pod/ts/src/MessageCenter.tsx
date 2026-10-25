import {useEffect,useState} from 'react';
import {Alert,Button,Space,Table,Tabs,Tag} from 'antd';
import {ReloadOutlined} from '@ant-design/icons';
import {locale,t} from './i18n';
import {Alarms} from './Alarms';
import type {EnerCubixApi} from './api';
import type {EnerCubixRecord} from './types';
import {changeActionLabel,changeCategoryLabel,changeFieldLabel,changeValue,type ChangeMessage,type ChangeMessagePage} from './changeMessages';

function ChangeMessages({api,records}:{api:EnerCubixApi;records:EnerCubixRecord[]}){
 const[page,setPage]=useState(1);const[refresh,setRefresh]=useState(0);
 const[data,setData]=useState<ChangeMessagePage>({items:[],total:0,offset:0,limit:30});
 const[loading,setLoading]=useState(false);const[error,setError]=useState('');
 useEffect(()=>{
  const controller=new AbortController();setLoading(true);setError('');
  void api.changeMessages((page-1)*30,30,controller.signal).then(result=>{if(!controller.signal.aborted)setData(result);}).catch(error=>{if(!controller.signal.aborted){setData({items:[],total:0,offset:(page-1)*30,limit:30});setError(error instanceof Error?error.message:t('无法读取变更记录'));}}).finally(()=>{if(!controller.signal.aborted)setLoading(false);});
  return()=>controller.abort();
 },[api,page,refresh]);
 return <section className="change-messages">
  <div className="workspace-title"><div><h3>{t('重要变更')}</h3><p>{t('查看关系、来源及关键配置的变更；日志不参与统计计算。')}</p></div><Button aria-label={t('刷新记录')} icon={<ReloadOutlined/>} loading={loading} onClick={()=>setRefresh(value=>value+1)}>{t('刷新记录')}</Button></div>
  {error&&<Alert type="error" showIcon message={error}/>}
  <Space className="management-tools"><Tag>{t('共 {0} 条',data.total)}</Tag></Space>
  <Table<ChangeMessage> size="middle" rowKey="id" loading={loading} dataSource={data.items} scroll={{x:'max-content'}} locale={{emptyText:t('暂无重要变更记录')}} pagination={{current:page,pageSize:30,total:data.total,showSizeChanger:false,onChange:setPage}}
   columns={[
    {title:t('时间'),dataIndex:'ts',render:(value:string)=>new Date(value).toLocaleString(locale)},
    {title:t('消息类型'),dataIndex:'category',render:(value:string)=><Tag color="blue">{changeCategoryLabel(value)}</Tag>},
    {title:t('对象'),dataIndex:'objectName'},
    {title:t('变更操作'),dataIndex:'action',render:changeActionLabel},
    {title:t('变更内容'),render:(_,record)=><span>{record.changes.map(change=>changeFieldLabel(change.field)).join(locale==='zh-CN'?'、':', ')}{record.detailsRestricted&&<Tag>{t('部分详情已隐藏')}</Tag>}</span>},
    {title:t('操作人'),dataIndex:'actor',render:(value?:string)=>value||t('未记录')}
   ]}
   expandable={{rowExpandable:record=>record.changes.length>0,expandedRowRender:record=><Table size="small" rowKey="field" pagination={false} dataSource={record.changes} scroll={{x:'max-content'}} columns={[
    {title:t('变更字段'),dataIndex:'field',render:changeFieldLabel},
    {title:t('修改前'),dataIndex:'before',render:(value,change)=>changeValue(change.field,value,records)},
    {title:t('修改后'),dataIndex:'after',render:(value,change)=>changeValue(change.field,value,records)}
   ]}/>}}
  />
 </section>;
}

export function MessageCenter({api,canWrite,records}:{api:EnerCubixApi;canWrite:boolean;records:EnerCubixRecord[]}){
 return <div className="management message-center"><div className="workspace-title"><div><h2>{t('消息中心')}</h2><p>{t('查看能耗报警和重要变更记录。')}</p></div></div>
  <Tabs defaultActiveKey="alarms" items={[
   {key:'alarms',label:t('报警'),children:<Alarms api={api} canWrite={canWrite} records={records}/>},
   {key:'changes',label:t('重要变更'),children:<ChangeMessages api={api} records={records}/>}
  ]}/>
 </div>;
}
