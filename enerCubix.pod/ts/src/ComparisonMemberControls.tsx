import {useEffect,useState} from 'react';
import {Alert,Button,Select,Space,Spin,Tag,Typography} from 'antd';
import {serverMessage,t} from './i18n';
import type {EnerCubixApi} from './api';
import type {ComparisonScope,EnerCubixRecord} from './types';

interface Props {api:EnerCubixApi;nodeIds:string[];records:EnerCubixRecord[];members:Record<string,string[]>;onChange:(members:Record<string,string[]>)=>void}
export function ComparisonMemberControls({api,nodeIds,records,members,onChange}:Props){
 const key=JSON.stringify(nodeIds);
 const[state,setState]=useState<{key:string;scopes:ComparisonScope[];loading:boolean;error:string}>({key:'',scopes:[],loading:false,error:''});
 useEffect(()=>{
  const ids=JSON.parse(key) as string[];if(!ids.length)return;
  const abort=new AbortController();let active=true;
  setState({key,scopes:[],loading:true,error:''});
  void api.comparisonScopes(ids,abort.signal).then(result=>{if(active)setState({key,scopes:result.scopes,loading:false,error:''});},error=>{if(active&&error?.name!=='AbortError')setState({key,scopes:[],loading:false,error:error instanceof Error?error.message:t('比较范围读取失败，请重新选择对象或查询。')});});
  return()=>{active=false;abort.abort();};
 },[api,key]);
 if(!nodeIds.length)return null;
 const current=state.key===key?state:undefined;
 const update=(id:string,values:string[]|undefined)=>{const next={...members};if(values===undefined)delete next[id];else next[id]=values;onChange(next);};
 return <section className="comparison-members"><Typography.Text strong>{t('本次总分表比较范围')}</Typography.Text><p>{t('比较分表由服务端按物理计量边界解析，不受“计入合计”开关限制。临时选择仅用于本次查询和模板，不修改表计配置。')}</p>
  <Spin spinning={!current||current.loading}>
   {current?.error&&<Alert type="warning" showIcon message={current.error}/>}
   {current&&!current.loading&&!current.error&&!current.scopes.length&&<Alert type="info" message={t('未解析到可比较的分表；仍可查询各表自身已有用量。')}/>}
   {current?.scopes.map(scope=>{const explicit=Object.hasOwn(members,scope.nodeId),selected=explicit?members[scope.nodeId]:scope.defaultMemberIds;const available=new Set(scope.availableMembers.map(member=>member.nodeId));const name=records.find(record=>record.id===scope.nodeId)?.name||t('计量对象');return <div className="comparison-member-field" key={scope.nodeId}>
    <Space wrap><Typography.Text strong>{name}</Typography.Text><Tag>{explicit?selected.length?t('已自选 {0} 个分表',selected.length):t('已明确不选分表'):t('默认全部 {0} 个分表',scope.defaultMemberIds.length)}</Tag></Space>
    <Select mode="multiple" allowClear showSearch optionFilterProp="label" aria-label={t('{0}的比较分表',name)} value={selected.filter(id=>available.has(id))} onChange={values=>update(scope.nodeId,values)} options={scope.availableMembers.map(member=>({value:member.nodeId,label:member.name}))} placeholder={t('不选分表')} style={{width:'100%'}}/>
    <Space wrap><Button size="small" type="link" onClick={()=>update(scope.nodeId,undefined)}>{t('恢复默认全部')}</Button><Button size="small" type="link" onClick={()=>update(scope.nodeId,[])}>{t('不选分表')}</Button></Space>
    {selected.some(id=>!available.has(id))&&<Alert type="warning" showIcon message={t('已保存的选择包含当前不可用的分表，请重新选择；系统不会自动扩大比较范围。')}/>}
    {(scope.quality!=='ok'||!!scope.limitations?.length)&&<Alert type="info" showIcon message={[scope.quality!=='ok'?serverMessage(scope.quality):'',...(scope.limitations||[]).map(serverMessage)].filter(Boolean).join(t('；'))}/>}
    {!scope.availableMembers.length&&<Typography.Text type="secondary">{t('未解析到可比较的分表；仍可查询各表自身已有用量。')}</Typography.Text>}
    {explicit&&<Typography.Text type="secondary">{t('未覆盖完整物理边界时，仅展示已有用量，不据此判定泄漏。')}</Typography.Text>}
   </div>;})}
  </Spin>
 </section>;
}
