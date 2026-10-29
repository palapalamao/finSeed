import '@ant-design/v5-patch-for-react-19';
import React from 'react';
import ReactDOM from 'react-dom/client';
import {initializeLocale,t} from './i18n';
import {loadFinSession} from './session';
import './styles.css';
import './enercubix.css';
async function bootstrap(){
 const root=document.getElementById('root')!;
 root.textContent='…';
 try{
  const session=await loadFinSession(location);
  initializeLocale(session.locale,session.username);
  const {App}=await import('./App');
  ReactDOM.createRoot(root).render(<React.StrictMode><App/></React.StrictMode>);
 }catch(error){
  initializeLocale('en');
  const message=document.createElement('p');
  message.setAttribute('role','alert');
  message.textContent=error instanceof Error?error.message:t('无法读取 FIN 用户语言，请重新打开应用。');
  const retry=document.createElement('button');
  retry.textContent=t('重新连接');retry.onclick=()=>location.reload();
  root.replaceChildren(message,retry);
 }
}
void bootstrap();
