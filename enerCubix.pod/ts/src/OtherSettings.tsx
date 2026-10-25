import {useEffect,useState} from 'react';
import {Alert,Button,Form,InputNumber,Tabs,message} from 'antd';
import {t} from './i18n';
import type {EnerCubixApi} from './api';
import type {Catalog} from './types';
import {recordDefaults} from './RecordEditor';
import {meterRollupSeconds} from './settings';
import {CleaningProfiles} from './CleaningProfiles';

export function OtherSettings({api,catalog,reload}:{api:EnerCubixApi;catalog:Catalog;reload:()=>Promise<void>}){
 const [form]=Form.useForm();const [saving,setSaving]=useState(false);
 const settings=catalog.records.find(row=>row.kind==='settings');
 useEffect(()=>{form.setFieldsValue({meterRollupSeconds:meterRollupSeconds(catalog.records)});},[form,catalog.records]);
 const save=async(values:{meterRollupSeconds:number})=>{
  setSaving(true);
  try{
   await api.save({name:t('系统设置'),...recordDefaults('settings'),...settings,kind:'settings',meterRollupSeconds:values.meterRollupSeconds});
   await reload();message.success(t('配置已保存到 FIN'));
  }catch(error){message.error(error instanceof Error?error.message:t('保存失败'));}
  finally{setSaving(false);}
 };
 return <div className="management"><div className="workspace-title"><div><h2>{t('其他配置')}</h2><p>{t('配置保存在当前 FIN 项目中，修改需要项目管理权限。')}</p></div></div>
  {!catalog.user.canWrite&&<Alert type="info" showIcon message={t('当前 FIN 用户为只读权限，可查看配置；新增、修改和删除由管理员执行。')}/>}
  <Tabs items={[{key:'general',label:t('计算设置'),children:<Form form={form} layout="vertical" disabled={!catalog.user.canWrite||saving} onFinish={values=>void save(values)} style={{maxWidth:640}}>
   <Form.Item name="meterRollupSeconds" label={t('计算总表更新间隔（秒）')} rules={[{required:true,type:'integer',min:1,max:3600,message:t('请输入 1 至 3600 的整数秒数')}]} extra={t('默认每 1 秒更新，可设置为 1 至 3600 秒；保存后后台自动生效。')}>
    <InputNumber aria-label={t('计算总表更新间隔（秒）')} min={1} max={3600} step={1} style={{width:'100%'}}/>
   </Form.Item>
   <Alert type="info" showIcon message={t('仅更新已开启“按分表计算当前值”的计算总表；实测总表请保持关闭。')} description={t('此设置控制当前值计算，不改变采集频率或历史记录间隔。')}/>
   <Form.Item style={{marginTop:20}}><Button type="primary" htmlType="submit" disabled={!catalog.user.canWrite} loading={saving}>{t('保存配置')}</Button></Form.Item>
  </Form>},{key:'cleaning',label:t('数据清洗方案'),children:<CleaningProfiles api={api} catalog={catalog} reload={reload}/>} ]}/>
 </div>;
}
