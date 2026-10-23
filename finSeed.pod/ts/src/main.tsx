import '@ant-design/v5-patch-for-react-19';
import React from 'react';
import ReactDOM from 'react-dom/client';
import {initializeLocale} from './i18n';
import {App} from './App';
import './styles.css';
import './enercubix.css';
initializeLocale();
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
