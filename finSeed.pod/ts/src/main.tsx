import '@ant-design/v5-patch-for-react-19';
import React from 'react';
import ReactDOM from 'react-dom/client';
import 'dayjs/locale/zh-cn';
import dayjs from 'dayjs';
import {App} from './App';
import './styles.css';
dayjs.locale('zh-cn');
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
