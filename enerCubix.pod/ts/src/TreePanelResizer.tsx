import {t} from './i18n';
import {useLayoutEffect,useRef,useState,type PointerEvent} from 'react';

const minWidth=180;
export function TreePanelResizer({scope,label}:{scope:'analysis'|'metering';label:string}){
 const storageKey=`enerCubix:tree-width:v1:${scope}`;
 const handle=useRef<HTMLDivElement>(null);
 const drag=useRef<{x:number;width:number;current:number}|undefined>(undefined);
 const[preferred,setPreferred]=useState<number|undefined>(()=>{try{const value=Number(localStorage.getItem(storageKey));return Number.isFinite(value)&&value>=minWidth?value:undefined;}catch{return undefined;}});
 const[limits,setLimits]=useState({max:minWidth,defaultWidth:minWidth});
 const width=Math.min(limits.max,Math.max(minWidth,preferred??limits.defaultWidth));
 useLayoutEffect(()=>{
  const panel=handle.current!.parentElement!,root=panel.parentElement!;
  const update=()=>{
   const details=root.querySelector<HTMLElement>(':scope > .meter-detail-panel');
   const max=Math.max(minWidth,Math.floor(root.clientWidth-(details?.getBoundingClientRect().width||0)-(scope==='analysis'?480:320)));
   const defaultWidth=parseFloat(getComputedStyle(root).getPropertyValue('--enerCubix-tree-default-width'))||panel.getBoundingClientRect().width;
   setLimits(previous=>previous.max===max&&previous.defaultWidth===defaultWidth?previous:{max,defaultWidth});
  };
  const observer=new ResizeObserver(update);observer.observe(root);update();
  return()=>{observer.disconnect();root.style.removeProperty('--enerCubix-tree-width');};
 },[]);
 useLayoutEffect(()=>{
  const root=handle.current!.parentElement!.parentElement!;
  if(preferred===undefined)root.style.removeProperty('--enerCubix-tree-width');else root.style.setProperty('--enerCubix-tree-width',`${width}px`);
 },[preferred,width]);
 const clamp=(value:number)=>Math.round(Math.min(limits.max,Math.max(minWidth,value)));
 const save=(value:number)=>{setPreferred(value);try{localStorage.setItem(storageKey,String(value));}catch{/* Resizing remains usable when browser storage is disabled. */}};
 const finish=(event:PointerEvent<HTMLDivElement>)=>{if(!drag.current)return;save(drag.current.current);drag.current=undefined;if(event.currentTarget.hasPointerCapture(event.pointerId))event.currentTarget.releasePointerCapture(event.pointerId);};
 return <div ref={handle} className="tree-panel-resizer" role="separator" aria-label={label} aria-orientation="vertical" aria-valuemin={minWidth} aria-valuemax={limits.max} aria-valuenow={Math.round(width)} tabIndex={0} title={t("拖动调整树面板宽度，也可使用左右方向键")}
  onPointerDown={event=>{if(event.button!==0)return;event.preventDefault();drag.current={x:event.clientX,width,current:width};event.currentTarget.setPointerCapture(event.pointerId);}}
  onPointerMove={event=>{if(!drag.current)return;const next=clamp(drag.current.width+event.clientX-drag.current.x);drag.current.current=next;setPreferred(next);}}
  onPointerUp={finish} onPointerCancel={finish}
  onKeyDown={event=>{const next=event.key==='ArrowLeft'?width-16:event.key==='ArrowRight'?width+16:event.key==='Home'?minWidth:event.key==='End'?limits.max:undefined;if(next===undefined)return;event.preventDefault();save(clamp(next));}}/>;
}
