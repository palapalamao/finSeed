import {Button,Dropdown} from 'antd';
import {GlobalOutlined} from '@ant-design/icons';
import {changeLanguage,languageDefinitions,languagePreference,locale,t,type LanguagePreference} from './i18n';

export function LanguageSwitcher(){
 const items=[{key:'auto',label:t('跟随系统')},{type:'divider' as const},...Object.entries(languageDefinitions).map(([key,language])=>({key,label:language.label}))];
 return <Dropdown trigger={['click']} menu={{items,selectable:true,selectedKeys:[languagePreference],onClick:({key})=>changeLanguage(key as LanguagePreference)}}>
  <Button type="text" className="language-switcher" icon={<GlobalOutlined/>} aria-label={t('切换语言')} title={t('切换语言将刷新当前页面')}><span className="language-label">{languageDefinitions[locale].label}</span></Button>
 </Dropdown>;
}
