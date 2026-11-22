import {describe,it,expect} from 'vitest';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {ReportDataTable,ReportTableDocument} from './reportTable';
const rows=Array.from({length:325},(_,i)=>({id:String(i),proof:'Proof-'+i}));
const render=(full:boolean)=>renderToStaticMarkup(createElement(ReportTableDocument.Provider,{value:full},createElement(ReportDataTable,{rowKey:'id',dataSource:rows,columns:[{dataIndex:'proof',title:'Proof'}]})));
describe('screen table pagination and complete document mode',()=>{
 it('bounds screen DOM to 100 rows while keeping all 325 rows in the data set',()=>{
  const before=structuredClone(rows),html=render(false);
  expect((html.match(/data-row-key=/g)||[]).length).toBe(100);expect(html).toContain('Proof-99');expect(html).not.toContain('Proof-324');expect(html).toContain('ant-pagination');expect(rows).toEqual(before);
 });
 it('renders every row and no page controls for a complete document',()=>{
  const html=render(true);expect((html.match(/data-row-key=/g)||[]).length).toBe(325);expect(html).toContain('Proof-324');expect(html).not.toContain('ant-pagination');
 });
});
