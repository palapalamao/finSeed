import {useCallback,useEffect,useRef,useState} from 'react';
import {Alert,Button,Card,Descriptions,Modal,Space,Spin,Tag,Typography,message} from 'antd';
import {DeleteOutlined,DownloadOutlined,ReloadOutlined,UploadOutlined} from '@ant-design/icons';
import type {EnerCubixApi} from './api';
import {locale,t} from './i18n';
import {createLicenseRequest,maxLicenseFileBytes,type LicenseStatus} from './license';
import './licenseSettings.css';

const statusLabels={
 trial:'免费使用',active:'已激活',expired:'授权已到期',invalid:'授权无效',
 notYetValid:'授权尚未生效',hostUnavailable:'FIN 机器码不可用'
} as const;

function localTime(value:string){
 const date=new Date(value);
 return Number.isFinite(date.valueOf())
  ?new Intl.DateTimeFormat(locale,{
   year:'numeric',month:'short',day:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit',timeZoneName:'short'
  }).format(date)
  :value;
}

export function LicenseDetails({status}:{status:LicenseStatus}){
 const format=new Intl.NumberFormat(locale);
 return <Space direction="vertical" size={16} className="license-details">
  {status.overLimit&&<Alert type="warning" showIcon message={t('项目已超出免费额度')}
   description={t('新查询、总表当前值合计及能耗报警扫描已暂停。导入有效授权，或把本项目纳管表减至 {0} 块以内即可恢复。',status.limit)}/>}
  <Card size="small">
   <Descriptions column={{xs:1,sm:2,lg:3}} layout="vertical" size="small">
    <Descriptions.Item label={t('授权状态')}><Tag color={status.status==='active'?'success':status.status==='trial'?'default':'warning'}>{t(statusLabels[status.status])}</Tag></Descriptions.Item>
    <Descriptions.Item label={t('本项目纳管表')}>
     {status.limit===null?t('{0} 块 · 无上限',format.format(status.used)):t('{0} / {1} 块',format.format(status.used),format.format(status.limit))}
    </Descriptions.Item>
    {status.licenseType&&<Descriptions.Item label={t('授权类型')}>{t(status.licenseType==='training'?'培训授权':'机器绑定授权')}</Descriptions.Item>}
    {status.notBefore&&<Descriptions.Item label={t('生效时间')}>{localTime(status.notBefore)}</Descriptions.Item>}
    {status.expiresAt&&<Descriptions.Item label={t('到期时间')}>{localTime(status.expiresAt)}</Descriptions.Item>}
    {status.licenseId&&<Descriptions.Item label={t('授权编号')}><span className="license-identity">{status.licenseId}</span></Descriptions.Item>}
   </Descriptions>
  </Card>
  {status.hostId&&<Card size="small" title={t('FIN 机器码')}>
   <Typography.Text className="license-identity" code copyable={{text:status.hostId,tooltips:[t('复制机器码'),t('已复制机器码')]}}>{status.hostId}</Typography.Text>
  </Card>}
 </Space>;
}

export function LicenseSettings({api}:{api:EnerCubixApi}){
 const [status,setStatus]=useState<LicenseStatus>();
 const [loading,setLoading]=useState(true);
 const [saving,setSaving]=useState(false);
 const [error,setError]=useState('');
 const [selectedFile,setSelectedFile]=useState<File>();
 const [dialog,setDialog]=useState<'add'|'delete'>();
 const fileInput=useRef<HTMLInputElement>(null);

 const refresh=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);
  setError('');
  try{
   const next=await api.licenseStatus(signal);
   if(!signal?.aborted)setStatus(next);
  }catch(error){
   if(!signal?.aborted)setError(error instanceof Error?error.message:t('无法读取授权状态'));
  }finally{
   if(!signal?.aborted)setLoading(false);
  }
 },[api]);
 useEffect(()=>{
  const controller=new AbortController();
  setStatus(undefined);
  setSelectedFile(undefined);
  setDialog(undefined);
  void refresh(controller.signal);
  return ()=>controller.abort();
 },[refresh]);

 const download=()=>{
  if(!status?.hostId)return;
  const blob=new Blob([JSON.stringify(createLicenseRequest(status.hostId),null,2)+'\n'],{type:'application/json'});
  const url=URL.createObjectURL(blob);
  const link=document.createElement('a');
  link.href=url;
  link.download='enercubix-request.json';
  link.click();
  setTimeout(()=>URL.revokeObjectURL(url),1000);
 };
 const openDialog=(next:'add'|'delete')=>{
  setError('');
  setSelectedFile(undefined);
  setDialog(next);
 };
 const closeDialog=()=>{
  if(saving)return;
  setError('');
  setSelectedFile(undefined);
  setDialog(undefined);
 };
 const activate=async()=>{
  if(!status?.canImport||!selectedFile||saving)return;
  setSaving(true);
  setError('');
  try{
   const next=await api.importLicense(await selectedFile.text());
   setStatus(next);
   setSelectedFile(undefined);
   setDialog(undefined);
   message.success(t('授权已导入并生效'));
  }catch(error){
   setError(error instanceof Error?error.message:t('无法导入授权文件'));
  }finally{setSaving(false);}
 };
 const remove=async()=>{
  if(!status?.canDelete||!status.deleteToken||saving)return;
  setSaving(true);
  setError('');
  try{
   setStatus(await api.deleteLicense(status.deleteToken));
   setDialog(undefined);
   message.success(t('授权已删除'));
  }catch(error){
   setDialog(undefined);
   try{setStatus(await api.licenseStatus());}catch{/* Keep the last verified status. */}
   setError(error instanceof Error?error.message:t('无法删除授权'));
  }finally{setSaving(false);}
 };

 return <section className="management license-settings">
  <div className="workspace-title">
   <div><h2>{t('授权管理')}</h2><p>{t('查看本项目的表计额度，管理当前 FIN 实例的授权。')}</p></div>
   <Button icon={<ReloadOutlined/>} disabled={saving||!!dialog} loading={loading} onClick={()=>void refresh()}>{t('刷新')}</Button>
  </div>
  <Space direction="vertical" size={16} className="license-details">
   {error&&!dialog&&<Alert type="error" showIcon message={error}/>}
   {!status&&loading&&<Spin aria-label={t('正在读取授权状态')}/>}
   {status&&<>
    <LicenseDetails status={status}/>
    <Space wrap>
     {status.hostId&&<Button icon={<DownloadOutlined/>} onClick={download}>{t('导出授权申请')}</Button>}
     {status.canImport&&<Button type="primary" icon={<UploadOutlined aria-hidden/>} disabled={loading||saving} onClick={()=>openDialog('add')}>{t('添加授权')}</Button>}
     {status.canDelete&&status.deleteToken&&<Button danger icon={<DeleteOutlined aria-hidden/>} disabled={loading||saving} onClick={()=>openDialog('delete')}>{t('删除授权')}</Button>}
    </Space>
    {status.hostId&&!status.canImport&&<Typography.Text type="secondary">{t('请联系 FIN 超级用户添加或删除授权。')}</Typography.Text>}
   </>}
  </Space>
  <Modal title={t('添加授权')} open={dialog==='add'} onCancel={closeDialog} onOk={()=>void activate()}
   okText={t('导入授权文件')} cancelText={t('取消')} confirmLoading={saving} okButtonProps={{disabled:!selectedFile}}
   closable={!saving} maskClosable={!saving} keyboard={!saving} cancelButtonProps={{disabled:saving}}>
   <Space direction="vertical" className="license-details">
    {status?.canDelete&&<Typography.Text>{t('导入有效文件后，将替换当前 FIN 实例的授权。')}</Typography.Text>}
    {error&&dialog==='add'&&<Alert type="error" showIcon message={error}/>}
    <input ref={fileInput} type="file" hidden accept=".json,.enercubix-license,application/json" onChange={event=>{
     const file=event.currentTarget.files?.[0];
     event.currentTarget.value='';
     setError(file&&file.size>maxLicenseFileBytes?t('授权文件不能超过 16 KB。'):'');
     setSelectedFile(file&&file.size<=maxLicenseFileBytes?file:undefined);
    }}/>
    <Button disabled={saving} onClick={()=>fileInput.current?.click()}>{t('选择授权文件')}</Button>
    {selectedFile&&<Typography.Text className="license-identity">{selectedFile.name}</Typography.Text>}
   </Space>
  </Modal>
  <Modal title={t('确认删除授权')} open={dialog==='delete'} onCancel={closeDialog} onOk={()=>void remove()}
   okText={t('删除授权')} cancelText={t('取消')} confirmLoading={saving} okButtonProps={{danger:true}}
   closable={!saving} maskClosable={!saving} keyboard={!saving} cancelButtonProps={{disabled:saving}}>
   <Typography.Paragraph>{t('删除后，当前 FIN 实例的所有项目将立即恢复各自的免费额度。超额项目会暂停新查询、当前值合计和能耗报警扫描。')}</Typography.Paragraph>
  </Modal>
 </section>;
}
