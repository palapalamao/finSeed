/** Decode only the negotiated cockpit wire representation. Legacy snapshots pass
 * through; reports and exports consume the same complete logical snapshot. */
export function decodeCockpitPayload<T>(input:unknown):T {
 const object=(value:unknown):value is Record<string,unknown>=>!!value&&typeof value==='object'&&!Array.isArray(value);
 const own=(value:object,key:string)=>Object.prototype.hasOwnProperty.call(value,key);
 const invalid=():never=>{throw new Error('invalid_response');};
 if(!object(input)||!own(input,'payloadEncoding'))return input as T;
 if(input.payloadEncoding!=='compact-v1'||input.codecVersion!==1||!object(input.snapshot)||!object(input.evidence))return invalid();
 const evidence=input.evidence,ids=Object.keys(evidence);
 if(ids.length>10000||ids.some(id=>!/^[a-f0-9]{64}$/.test(id)))return invalid();
 const memo=new Map<string,unknown>(),visiting=new Set<string>();
 let nodes=0,tables=0,rows=0,references=0;
 const assign=(target:Record<string,unknown>,key:string,value:unknown)=>Object.defineProperty(target,key,{value,writable:true,enumerable:true,configurable:true});
 const read=(value:unknown,depth:number):unknown=>{
  if(depth>80||++nodes>2000000)return invalid();
  if(Array.isArray(value))return value.map(cell=>read(cell,depth+1));
  if(!object(value))return value;
  if(own(value,'$cockpitLiteral')){
   const literal=value.$cockpitLiteral;
   if(Object.keys(value).length!==1||!object(literal))return invalid();
   const restored:Record<string,unknown>={};Object.entries(literal).forEach(([key,cell])=>assign(restored,key,read(cell,depth+1)));return restored;
  }
  if(own(value,'$cockpitRef')){
   const id=value.$cockpitRef;
   if(++references>10000||Object.keys(value).length!==1||typeof id!=='string'||!own(evidence,id)||visiting.has(id))return invalid();
   if(memo.has(id))return memo.get(id);
   visiting.add(id);const restored=read(evidence[id],depth+1);visiting.delete(id);memo.set(id,restored);return restored;
  }
  if(own(value,'$cockpitTable')){
   const table=value.$cockpitTable;
   if(++tables>512||Object.keys(value).length!==1||!object(table)||Object.keys(table).some(key=>!['columns','rows','constants'].includes(key))||!Array.isArray(table.columns)||!Array.isArray(table.rows)||own(table,'constants')&&!object(table.constants))return invalid();
   const columns=table.columns;
   const constants=object(table.constants)?table.constants:{},constantKeys=Object.keys(constants),fixed:Record<string,unknown>={};
   if(columns.length+constantKeys.length>64||columns.some(column=>typeof column!=='string')||new Set([...columns,...constantKeys]).size!==columns.length+constantKeys.length||(rows+=table.rows.length)>500000||nodes+constantKeys.length*table.rows.length>2000000)return invalid();
   constantKeys.forEach(key=>assign(fixed,key,read(constants[key],depth+1)));
   return table.rows.map(row=>{
    if(!Array.isArray(row)||row.length!==columns.length||(nodes+=constantKeys.length)>2000000)return invalid();
    const restored:Record<string,unknown>={};
    constantKeys.forEach(key=>assign(restored,key,fixed[key]));
    columns.forEach((column,index)=>assign(restored,column as string,read(row[index],depth+1)));
    return restored;
   });
  }
  const restored:Record<string,unknown>={};Object.entries(value).forEach(([key,cell])=>assign(restored,key,read(cell,depth+1)));return restored;
 };
 return read(input.snapshot,0) as T;
}
