import {useEffect} from 'react';
import {Alert,Button,Drawer,Form,InputNumber,Space} from 'antd';
import {t} from './i18n';
import type {EnerCubixRecord} from './types';
import {spaceAreaPayload} from './serviceArea';
interface Props {open:boolean;record:EnerCubixRecord;canWrite:boolean;saving:boolean;saveError?:string;onClose:()=>void;onSave:(record:EnerCubixRecord)=>Promise<void>}
export function SpaceAreaEditor({open,record,canWrite,saving,saveError,onClose,onSave}:Props){
 const [form]=Form.useForm();
 useEffect(()=>{form.resetFields();form.setFieldsValue({area:record.area});},[form,record,open]);
 return <Drawer aria-label={t('编辑空间面积：{0}',record.name)} open={open} onClose={onClose} title={t('编辑空间面积：{0}',record.name)} width={520} extra={<Space><Button onClick={onClose}>{t('取消')}</Button><Button type="primary" loading={saving} disabled={!canWrite} onClick={()=>form.submit()}>{t('保存配置')}</Button></Space>} destroyOnClose>
  <Alert type="info" showIcon message={t('面积保存到此 FIN 楼宇或楼层的 area 标签，单位为 m²。清空后单位面积指标将不可用。')}/>
  {saveError&&<Alert type="error" role="alert" message={saveError}/>}
  <Form form={form} layout="vertical" disabled={!canWrite} onFinish={values=>void onSave(spaceAreaPayload(record,values.area??null))}>
   <Form.Item name="area" label={t('建筑面积 (m²)')} rules={[{validator:(_,value)=>value===null||value===undefined||typeof value==='number'&&Number.isFinite(value)&&value>0?Promise.resolve():Promise.reject(new Error(t('面积必须为大于零的有限数值')))}]}><InputNumber aria-label={t('建筑面积 (m²)')} min={0} style={{width:'100%'}}/></Form.Item>
  </Form>
 </Drawer>;
}
