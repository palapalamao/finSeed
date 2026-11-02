import {Button,Dropdown,message} from 'antd';
import {GlobalOutlined} from '@ant-design/icons';
import {changeLanguage,languageDefinitions,languagePreference,locale,t,type LanguagePreference} from './i18n';

export function LanguageSwitcher({inPlace=false,disabled=false}:{inPlace?:boolean;disabled?:boolean}={}){
 const items=[{key:'auto',label:t('跟随 FIN 用户语言')},{type:'divider' as const},...Object.entries(languageDefinitions).map(([key,language])=>({key,label:language.label}))];
 return <Dropdown transitionName="" disabled={disabled} trigger={['click']} menu={{items,selectable:true,selectedKeys:[languagePreference],onClick:({key})=>{
  try{changeLanguage(key as LanguagePreference,{inPlace});}catch(error){void message.error(error instanceof Error?error.message:t('无法保存语言设置，请检查浏览器的站点存储权限。'));}
 }}}>
  <Button disabled={disabled} type="text" className="language-switcher" icon={<GlobalOutlined/>} aria-label={t('切换语言')} title={inPlace?t('切换语言保留当前快照'):t('切换语言将刷新当前页面')}><span className="language-label">{languageDefinitions[locale].label}</span></Button>
 </Dropdown>;
}
