import {afterEach,describe,expect,it,vi} from 'vitest';
import {Workbook} from 'exceljs';
import JSZip from 'jszip';

const originalBrowserFlag=Object.getOwnPropertyDescriptor(process,'browser');
afterEach(()=>{if(originalBrowserFlag)Object.defineProperty(process,'browser',originalBrowserFlag);else Reflect.deleteProperty(process,'browser');vi.restoreAllMocks();vi.unstubAllGlobals();vi.resetModules();});

async function downloadWorkbook(language:string,coverage=false,longText=''){
 // Production runs ExcelJS's browser TextEncoder path; Node's ZIP string path differs.
 Object.defineProperty(process,'browser',{value:true,configurable:true});
 (await import('./i18n')).initializeLocale(language);
 vi.stubGlobal('document',{createElement:()=>({click:vi.fn(),href:'',download:''})});
 let downloaded:Blob|undefined;
 vi.spyOn(URL,'createObjectURL').mockImplementation(blob=>{downloaded=blob as Blob;return 'blob:export-test';});
 vi.spyOn(URL,'revokeObjectURL').mockImplementation(()=>{});
 const {makeSnapshot,exportXlsx,exportCoverageXlsx}=await import('./exports');
 const {t}=await import('./i18n');
 const request={kind:'leak' as const,nodeIds:['m'],from:'2026-10-24T00:00:00+08:00',to:'2026-10-25T00:00:00+08:00',period:'day' as const,metric:'energy' as const,perArea:false};
 const snapshot=makeSnapshot(request,{kind:'leak',from:request.from,to:request.to,period:'day',warnings:[],series:[],summary:{},rows:[{name:'Frozen meter',value:232908,diagnostic:longText}],extra:{diagnostic:longText}},'Balance','cubeTest',new Date('2026-10-25T00:00:00Z'));
 if(coverage)snapshot.project=longText;
 const frozen=structuredClone(snapshot);
 await (coverage?exportCoverageXlsx:exportXlsx)(snapshot);
 expect(snapshot).toEqual(frozen);
 const buffer=await downloaded!.arrayBuffer(),book=new Workbook();await book.xlsx.load(buffer);
 const zip=await JSZip.loadAsync(buffer),xml=new TextDecoder('utf-8',{fatal:true}).decode(await zip.file('xl/sharedStrings.xml')!.async('uint8array'));
 const strings=Array.from(xml.matchAll(/<si>([\s\S]*?)<\/si>/g),match=>Array.from(match[1].matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g),text=>text[1]).join('').replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&amp;','&'));
 const sheets=new Map(await Promise.all(book.worksheets.map(async sheet=>[sheet.id,await zip.file(`xl/worksheets/sheet${sheet.id}.xml`)!.async('string')] as const)));
 // Inspect the exact saved XML independently of ExcelJS's streaming parser.
 const savedText=(sheetId:number,address:string)=>{
  const cell=sheets.get(sheetId)!.match(new RegExp(`<c\\b[^>]*\\br="${address}"[^>]*>([\\s\\S]*?)<\\/c>`))?.[0];
  return cell?.includes('t="s"')?strings[Number(cell.match(/<v>(\d+)<\/v>/)![1])]:undefined;
 };
 return {book,t,snapshot,savedText};
}

function everyCellFits(book:Workbook){
 book.eachSheet(sheet=>sheet.eachRow(row=>row.eachCell(cell=>{
  if(typeof cell.value==='string')expect(cell.value.length,`${sheet.name}!${cell.address}`).toBeLessThanOrEqual(32767);
 })));
}

function originalText(book:Workbook,detailsName:string,sheetName:string,address:string,savedText?:(sheetId:number,address:string)=>string|undefined){
 const parts:string[]=[];
 const sheet=book.getWorksheet(detailsName)!;
 sheet.eachRow((row,index)=>{
  if(index>1&&row.getCell(1).value===sheetName&&row.getCell(2).value===address)parts.push(savedText?savedText(sheet.id,row.getCell(5).address)!:String(row.getCell(5).value));
 });
 return parts.join('');
}

describe('Excel text compatibility',()=>{
 it.each(['zh-CN','en-US'])('preserves every long metadata/detail cell and frozen values in %s',async language=>{
  const longText='x'.repeat(32766)+'😀<&>计量证据'+'z'.repeat(360000),{book,t,snapshot}=await downloadWorkbook(language,false,longText);
  everyCellFits(book);
  const info=book.getWorksheet(t('报表信息'))!,rows=book.getWorksheet(t('统计明细'))!;
  const extra=info.getRows(1,info.rowCount)!.find(row=>row.getCell(1).value===t('分析结果'))!;
  const actual=originalText(book,t('长文本明细'),info.name,extra.getCell(2).address),expected=JSON.stringify((await import('./reportDisplay')).readableReportValue(snapshot,'',snapshot.result.extra));
  expect(actual===expected).toBe(true);
  expect(originalText(book,t('长文本明细'),rows.name,'C2')).toBe(longText);
  expect(rows.getCell('A2').value).toBe('Frozen meter');expect(rows.getCell('B2').value).toBe('232908');
  expect(extra.getCell(2).note).toContain(t('长文本明细'));
  for(const sheet of book.worksheets)sheet.eachRow(row=>row.eachCell(cell=>{
   if(typeof cell.value==='string')expect(cell.value).not.toMatch(/^[\uDC00-\uDFFF]|[\uD800-\uDBFF]$/);
  }));
 });
 it('preserves large multilingual evidence in the actual XLSX XML without replacement characters',async()=>{
  const text='计量证据😀<&>'.repeat(70000),{book,t,snapshot,savedText}=await downloadWorkbook('zh-CN',false,text);
  const extra=book.getWorksheet(t('报表信息'))!.getRows(1,12)!.find(row=>row.getCell(1).value===t('分析结果'))!;
  const expected=JSON.stringify((await import('./reportDisplay')).readableReportValue(snapshot,'',snapshot.result.extra));
  const actual=originalText(book,t('长文本明细'),t('报表信息'),extra.getCell(2).address,savedText);
  expect(actual===expected).toBe(true);
  expect(originalText(book,t('长文本明细'),t('统计明细'),'C2',savedText)===text).toBe(true);
 });
 it.each(['zh-CN','en-US'])('protects coverage exports in %s too',async language=>{
  const longText='coverage原始证据'.repeat(12000),{book,t}=await downloadWorkbook(language,true,longText);
  everyCellFits(book);
  expect(originalText(book,t('长文本明细'),t('报表信息'),'B1')).toBe(longText);
 });
 it('leaves short text and the exact 32767-character boundary unchanged',async()=>{
  const text='x'.repeat(32767),{book,t}=await downloadWorkbook('en-US',false,text);
  const rows=book.getWorksheet(t('统计明细'))!;
  expect(rows.getCell('C2').value).toBe(text);expect(rows.getCell('C2').note).toBeUndefined();
  // The metadata JSON is longer than its leaf value, so it alone needs continuation.
  expect(originalText(book,t('长文本明细'),rows.name,'C2')).toBe('');
  expect(rows.getCell('A2').value).toBe('Frozen meter');expect(rows.getCell('B2').value).toBe('232908');
 });
 it('adds no continuation sheet to ordinary reports',async()=>{
  const {book,t}=await downloadWorkbook('zh-CN',false,'short diagnostic');
  expect(book.getWorksheet(t('长文本明细'))).toBeUndefined();
  expect(book.getWorksheet(t('统计明细'))!.getCell('C2').value).toBe('short diagnostic');
 });
});
