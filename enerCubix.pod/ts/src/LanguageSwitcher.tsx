import {Button,Dropdown,message} from 'antd';
import {GlobalOutlined} from '@ant-design/icons';
import {changeLanguage,languageDefinitions,languagePreference,locale,t,type LanguagePreference} from './i18n';

export function LanguageSwitcher(){
 const items=[{key:'auto',label:t('跟随 FIN 用户语言')},{type:'divider' as const},...Object.entries(languageDefinitions).map(([key,language])=>({key,label:language.label}))];
 return <Dropdown trigger={['click']} menu={{items,selectable:true,selectedKeys:[languagePreference],onClick:({key})=>{
  try{changeLanguage(key as LanguagePreference);}catch(error){void message.error(error instanceof Error?error.message:t('无法保存语言设置，请检查浏览器的站点存储权限。'));}
 }}}>
  <Button type="text" className="language-switcher" icon={<GlobalOutlined/>} aria-label={t('切换语言')} title={t('切换语言将刷新当前页面')}><span className="language-label">{languageDefinitions[locale].label}</span></Button>
 </Dropdown>;
}
