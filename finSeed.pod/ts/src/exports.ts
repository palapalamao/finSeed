import type {ReportRequest,ReportResult,ReportSnapshot} from './types';
export function makeSnapshot(request:ReportRequest,result:ReportResult,title:string,project:string,now=new Date()):ReportSnapshot {
 return structuredClone({request,result,title,project,generatedAt:now.toISOString()});
}
export function filterSnapshot(snapshot:ReportSnapshot|null,categoryIds:string[],categoryNames:string[]):ReportSnapshot|null{
 if(!snapshot||!categoryIds.length)return snapshot;
 const output=structuredClone(snapshot);const selected=new Set(categoryIds);const ids=new Set(output.result.series.filter(series=>selected.has(series.categoryId||'')).map(series=>series.id));
 const keep=(row:Record<string,unknown>)=>selected.has(String(row.categoryId||''))||ids.has(String(row.id||''))||categoryIds.some(category=>String(row.key||'').startsWith(`${category}|`));
 output.result.series=output.result.series.filter(series=>selected.has(series.categoryId||''));output.result.rows=output.result.rows.filter(keep);
 for(const object of [output.result.summary,output.result.extra])if(object)for(const[key,value]of Object.entries(object))if(Array.isArray(value)&&value.every(item=>item&&typeof item==='object'))object[key]=(value as Record<string,unknown>[]).filter(keep);
 output.categoryIds=[...categoryIds];output.categoryNames=[...categoryNames];return output;
}
export function cellText(value:unknown):string {if(value===null||value===undefined)return '—';if(typeof value==='object')return JSON.stringify(value);return String(value);}
export function reportTables(snapshot:ReportSnapshot){
 const rows=snapshot.result.rows;
 const headers=Array.from(new Set(rows.flatMap(row=>Object.keys(row))));
 return {headers,rows:rows.map(row=>headers.map(key=>cellText(row[key]))),series:[['对象','单位','时间','值','质量','源点'],...snapshot.result.series.flatMap(series=>series.points.map(point=>[series.name,series.unit,point.ts,point.value===null?'—':String(point.value),point.quality,point.sourceIds.join(', ')]))]};
}
function download(blob:Blob,name:string){const url=URL.createObjectURL(blob);const anchor=document.createElement('a');anchor.href=url;anchor.download=name;anchor.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function filename(snapshot:ReportSnapshot,extension:string){return `${snapshot.title}_${snapshot.project}_${snapshot.generatedAt.slice(0,10)}.${extension}`.replace(/[\\/:*?"<>|]/g,'_');}
const meta=(s:ReportSnapshot)=>[['项目',s.project],['报表',s.title],['分类筛选',s.categoryNames?.join('、')||'全部能源类型'],['区间起始（含）',s.result.from],['区间结束（不含）',s.result.to],['生成时间',s.generatedAt],['查询条件',JSON.stringify(s.request)],['汇总',JSON.stringify(s.result.summary)],['分析结果',JSON.stringify(s.result.extra||{})],['提示',s.result.warnings.join('\n')]];
export async function exportXlsx(snapshot:ReportSnapshot){
 const {Workbook}=await import('exceljs');const book=new Workbook();book.creator='FIN Seed';book.created=new Date(snapshot.generatedAt);const tables=reportTables(snapshot);
 for(const [name,data]of [['报表信息',meta(snapshot)],['统计明细',[tables.headers,...tables.rows]],['时序与质量',tables.series]] as [string,string[][]][]){const sheet=book.addWorksheet(name);sheet.addRows(data);sheet.views=[{state:'frozen',ySplit:1}];sheet.getRow(1).font={bold:true,color:{argb:'FFFFFFFF'}};sheet.getRow(1).fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF155C88'}};sheet.columns.forEach(column=>column.width=24);sheet.eachRow(row=>row.alignment={vertical:'top',wrapText:true});}
 const buffer=await book.xlsx.writeBuffer();download(new Blob([buffer as BlobPart],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}),filename(snapshot,'xlsx'));
}
export async function exportDocx(snapshot:ReportSnapshot){
 const {Document,Packer,Paragraph,TextRun,Table,TableRow,TableCell,WidthType,HeadingLevel}=await import('docx');const data=reportTables(snapshot);
 const table=(rows:string[][])=>new Table({width:{size:100,type:WidthType.PERCENTAGE},rows:rows.map((row,index)=>new TableRow({children:row.map(text=>new TableCell({children:[new Paragraph({children:[new TextRun({text,bold:index===0,size:18})]})]}))}))});
 const doc=new Document({creator:'FIN Seed',title:snapshot.title,styles:{default:{document:{run:{font:'Microsoft YaHei',size:20}}}},sections:[{properties:{page:{size:{orientation:'landscape'},margin:{top:700,bottom:700,left:700,right:700}}},children:[new Paragraph({text:snapshot.title,heading:HeadingLevel.TITLE}),...meta(snapshot).map(([key,value])=>new Paragraph(`${key}：${value}`)),new Paragraph({text:'统计明细',heading:HeadingLevel.HEADING_1}),...(data.headers.length?[table([data.headers,...data.rows])]:[new Paragraph('无统计明细')]),new Paragraph({text:'时序与质量',heading:HeadingLevel.HEADING_1}),table(data.series)]}]});
 download(await Packer.toBlob(doc),filename(snapshot,'docx'));
}
function prepareReport(element:HTMLElement){
 const clone=element.cloneNode(true) as HTMLElement;const width=Math.max(1100,element.scrollWidth,...Array.from(element.querySelectorAll<HTMLElement>('.ant-table-content')).map(table=>table.scrollWidth+48));
 clone.querySelectorAll('[data-export-ignore="true"]').forEach(node=>node.remove());
 Object.assign(clone.style,{position:'fixed',left:'-100000px',top:'0',width:`${width}px`,height:'auto',maxHeight:'none',overflow:'visible'});
 clone.querySelectorAll<HTMLElement>('.ant-table-content,.ant-table-container').forEach(node=>Object.assign(node.style,{overflow:'visible',maxHeight:'none'}));
 clone.querySelectorAll('details').forEach(details=>details.open=true);
 const sourceCanvases=element.querySelectorAll('canvas');clone.querySelectorAll('canvas').forEach((canvas,index)=>{const source=sourceCanvases[index];if(source){canvas.width=source.width;canvas.height=source.height;canvas.getContext('2d')?.drawImage(source,0,0);}});
 document.body.appendChild(clone);return clone;
}
export async function exportImage(snapshot:ReportSnapshot,element:HTMLElement){
 const {toPng}=await import('html-to-image');const clone=prepareReport(element);
 try{
  // PNG is an explicitly scoped chart-and-summary image. Full rows remain in XLSX, DOCX and paginated PDF.
  clone.querySelectorAll('.ant-table-wrapper,.table-heading,.quality-details').forEach(node=>node.remove());
  const sources=document.createElement('div');sources.className='snapshot-foot';const heading=document.createElement('strong');heading.textContent='曲线质量与来源摘要';sources.appendChild(heading);snapshot.result.series.forEach(series=>{const line=document.createElement('p');line.textContent=`${series.name}：${Array.from(new Set(series.points.map(point=>point.quality))).join('、')}；源点：${Array.from(new Set(series.points.flatMap(point=>point.sourceIds))).join('、')||'未提供'}`;sources.appendChild(line);});clone.appendChild(sources);
  const note=document.createElement('p');note.className='snapshot-foot';note.textContent=`图片范围：图表与摘要。完整 ${snapshot.result.rows.length} 条统计记录与时序质量、源点明细请导出 Excel、Word 或 PDF。`;clone.appendChild(note);
  const height=clone.scrollHeight;if(height*1.5>30000)throw new Error('图表摘要超过图片尺寸限制，请使用分页 PDF 或完整 Excel / Word 导出。');
  const url=await toPng(clone,{backgroundColor:'#fff',pixelRatio:1.5,style:{position:'static',left:'0',top:'0'}});const a=document.createElement('a');a.href=url;a.download=filename(snapshot,'png');a.click();
 }finally{clone.remove();}
}
export async function exportPdf(snapshot:ReportSnapshot,element:HTMLElement){
 const [{toPng},{jsPDF}]=await Promise.all([import('html-to-image'),import('jspdf')]);const clone=prepareReport(element);const doc=new jsPDF({orientation:'landscape',unit:'mm',format:'a4',compress:true});const margin=10;const imageWidth=doc.internal.pageSize.getWidth()-margin*2;const usable=doc.internal.pageSize.getHeight()-margin*2;
 const viewport=document.createElement('div');const width=clone.scrollWidth;Object.assign(viewport.style,{position:'fixed',left:'-100000px',top:'0',width:`${width}px`,overflow:'hidden',background:'#fff'});document.body.appendChild(viewport);Object.assign(clone.style,{position:'relative',left:'0',top:'0',margin:'0'});viewport.appendChild(clone);
 try{
  const height=clone.scrollHeight;const pagePixels=usable*width/imageWidth;const top=clone.getBoundingClientRect().top;
  clone.querySelectorAll('table').forEach(table=>{const headers=table.querySelector('thead tr')?.children;if(!headers)return;const widths=Array.from(headers).map(cell=>cell.getBoundingClientRect().width);let columns=table.querySelector('colgroup');if(!columns){columns=document.createElement('colgroup');table.prepend(columns);}columns.replaceChildren(...widths.map(value=>{const col=document.createElement('col');col.style.width=`${value}px`;return col;}));table.style.width=`${table.getBoundingClientRect().width}px`;table.style.tableLayout='fixed';});
  const bodies=Array.from(clone.querySelectorAll('tbody')).map(body=>({body,rows:Array.from(body.rows).map(row=>{const rect=row.getBoundingClientRect();return {node:row,top:rect.top-top,bottom:rect.bottom-top,height:rect.height};})}));
  const breaks=bodies.flatMap(body=>body.rows.map(row=>row.top)).filter(value=>value>0).sort((a,b)=>a-b);let offset=0,page=0;
  const spacer=(pixels:number,columns:number)=>{const row=document.createElement('tr');const cell=document.createElement('td');cell.colSpan=Math.max(columns,1);Object.assign(cell.style,{height:`${pixels}px`,padding:'0',border:'0',fontSize:'0',lineHeight:'0'});row.appendChild(cell);return row;};
  while(offset<height){let end=Math.min(height,offset+pagePixels);if(end<height){const boundary=breaks.filter(value=>value>offset+pagePixels*.35&&value<=end).at(-1);if(boundary!==undefined)end=boundary;}const slice=end-offset;viewport.style.height=`${slice}px`;clone.style.transform=`translateY(-${offset}px)`;
   // Preserve table geometry with spacers while serializing only the rows intersecting this page.
   bodies.forEach(({body,rows})=>{const before=rows.filter(row=>row.bottom<=offset);const visible=rows.filter(row=>row.bottom>offset&&row.top<end);const after=rows.filter(row=>row.top>=end);const columns=rows[0]?.node.cells.length||1;body.replaceChildren(...(before.length?[spacer(before.reduce((sum,row)=>sum+row.height,0),columns)]:[]),...visible.map(row=>row.node),...(after.length?[spacer(after.reduce((sum,row)=>sum+row.height,0),columns)]:[]));});
   // Rasterize one bounded page at a time; never allocate a canvas proportional to the full report height.
   const url=await toPng(viewport,{backgroundColor:'#fff',pixelRatio:1.25,width,height:Math.ceil(slice),style:{position:'static',left:'0',top:'0'}});if(page++)doc.addPage();doc.addImage(url,'PNG',margin,margin,imageWidth,slice*imageWidth/width,undefined,'FAST');doc.setFontSize(8);doc.text(`${page}`,doc.internal.pageSize.getWidth()-15,doc.internal.pageSize.getHeight()-4);offset=end;
  }
  doc.save(filename(snapshot,'pdf'));
 }finally{viewport.remove();clone.remove();}
}
