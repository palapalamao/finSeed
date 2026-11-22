import {createContext,useContext,useState} from 'react';
import {Table,type TableProps} from 'antd';
import {t} from './i18n';

// Document mode is set synchronously before native printing or DOM capture.
// Pagination changes only screen presentation, never the frozen report rows.
export const ReportTableDocument=createContext(false);
export function ReportDataTable<Row extends object>(props:TableProps<Row>){
 const full=useContext(ReportTableDocument),[page,setPage]=useState(1),count=props.dataSource?.length||0;
 const paged=!full&&count>100,current=Math.min(page,Math.max(1,Math.ceil(count/100)));
 return <div data-report-table-mode={full?'document':'screen'} data-report-table-rows={count}>
  <Table<Row> {...props} pagination={paged?{current,pageSize:100,showSizeChanger:false,showQuickJumper:true,showTotal:total=>t('共 {0} 条',total),onChange:setPage}:false}/>
 </div>;
}
