import {useCallback,useEffect,useState} from 'react';
import {Alert,Button,Card,Descriptions,Space,Spin,Tag,Typography} from 'antd';
import {ReloadOutlined} from '@ant-design/icons';
import type {FinEnergyApi} from './api';
import {serverMessage,t} from './i18n';
import type {LicenseStatus} from './license';
import './licenseSettings.css';

const statusLabels={active:'功能已授权',missingFeature:'未包含能源功能',invalid:'FIN 授权无效',inactive:'FIN 授权未生效'} as const;

export function LicenseDetails({status}:{status:LicenseStatus}){
 return <Space direction="vertical" size={16} className="license-details">
  <Card size="small">
   <Descriptions column={{xs:1,sm:2,lg:3}} layout="vertical" size="small">
    <Descriptions.Item label={t('授权状态')}><Tag color={status.status==='active'?'success':'warning'}>{t(statusLabels[status.status])}</Tag></Descriptions.Item>
    <Descriptions.Item label={t('授权来源')}>{t('FIN 原生授权')}</Descriptions.Item>
    <Descriptions.Item label={t('功能标识')}><Typography.Text code>{status.feature}</Typography.Text></Descriptions.Item>
   </Descriptions>
  </Card>
  {status.status!=='active'&&<Alert type="warning" showIcon message={t('需要 FIN 能源功能授权')}
   description={status.reason?serverMessage(status.reason):t('请联系 FIN 授权管理员，将能源功能加入当前 FIN 实例的原生授权。')}/>}
  {status.hostId&&<Card size="small" title={t('FIN 机器码')}>
   <Typography.Text className="license-identity" code copyable={{text:status.hostId,tooltips:[t('复制机器码'),t('已复制机器码')]}}>{status.hostId}</Typography.Text>
  </Card>}
  <Card size="small" title={t('管理 FIN 授权')}>
   <Typography.Paragraph>{t('授权的添加、更新、到期和删除由 FIN 原生授权系统统一管理。')}</Typography.Paragraph>
   <Typography.Paragraph className="license-native-path">{t('FIN 主菜单 → Host → Licenses')}</Typography.Paragraph>
   <Typography.Text type="secondary">{t(status.canManageFinLicense?'在 FIN 中打开 Host → Licenses 查看或更新原生授权；完成后返回此页刷新。':'请联系 FIN 授权管理员，在 Host → Licenses 中查看或更新原生授权。')}</Typography.Text>
  </Card>
 </Space>;
}

export function LicenseSettings({api}:{api:FinEnergyApi}){
 const [status,setStatus]=useState<LicenseStatus>();
 const [loading,setLoading]=useState(true);
 const [error,setError]=useState('');
 const refresh=useCallback(async(signal?:AbortSignal)=>{
  setLoading(true);setError('');
  try{const next=await api.licenseStatus(signal);if(!signal?.aborted)setStatus(next);}
  catch(error){if(!signal?.aborted)setError(error instanceof Error?error.message:t('无法读取授权状态'));}
  finally{if(!signal?.aborted)setLoading(false);}
 },[api]);
 useEffect(()=>{const controller=new AbortController();setStatus(undefined);void refresh(controller.signal);return()=>controller.abort();},[refresh]);
 return <section className="management license-settings">
  <div className="workspace-title">
   <div><h2>{t('授权管理')}</h2><p>{t('查看当前 FIN 实例的原生能源功能授权与机器码。')}</p></div>
   <Button icon={<ReloadOutlined/>} loading={loading} onClick={()=>void refresh()}>{t('刷新')}</Button>
  </div>
  <Space direction="vertical" size={16} className="license-details">
   {error&&<Alert type="error" showIcon message={error}/>}
   {!status&&loading&&<Spin aria-label={t('正在读取授权状态')}/>}
   {status&&<LicenseDetails status={status}/>}
  </Space>
 </section>;
}
