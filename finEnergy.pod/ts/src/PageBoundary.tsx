import {Component,Suspense,type ReactNode} from 'react';
import {Alert,Button,Spin} from 'antd';
import {t} from './i18n';

/** A failed page download leaves navigation and a localized recovery action usable. */
export class PageBoundary extends Component<{children:ReactNode},{failed:boolean}>{
 state={failed:false};
 static getDerivedStateFromError(){return {failed:true};}
 render(){
  return this.state.failed?<div className="connection-state"><Alert type="error" showIcon message={t('页面加载失败，请重新加载。')}/><Button onClick={()=>location.reload()}>{t('重新加载页面')}</Button></div>:<Suspense fallback={<div className="connection-state" role="status"><Spin tip={t('正在加载页面…')}/></div>}>{this.props.children}</Suspense>;
 }
}
