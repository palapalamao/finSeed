import type {CockpitSpaceNode} from './cockpitTypes';
import {cockpitMetricValue} from './cockpitMetrics';
import {t} from './i18n';

/** A diagram of real references, never a floor plan or a source of calculated energy. */
export function CockpitIsometricSpace({sites,focusedId,onFocus,path}:{sites:{site:CockpitSpaceNode;floors:CockpitSpaceNode[]}[];focusedId?:string;onFocus:(id:string)=>void;path:(id:string)=>string}){
 const columns=Math.min(3,sites.length),rows=Math.ceil(sites.length/columns),width=Math.max(420,columns*250),rowHeight=Math.max(310,...sites.map(({floors})=>floors.length*24+120)),height=rowHeight*rows;
 const activate=(node:CockpitSpaceNode)=>({role:'button',tabIndex:0,'aria-label':path(node.id),'aria-pressed':focusedId===node.id,'data-space-object':node.id,onClick:()=>onFocus(node.id),onKeyDown:(event:React.KeyboardEvent<SVGGElement>)=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();onFocus(node.id);}}});
 return <div className="cockpit-space-schematic"><svg className="cockpit-isometric" viewBox={`0 0 ${width} ${height}`} style={{minWidth:width,height:height*250/310}} role="group" aria-label={t('真实站点与楼层示意')}>
  <title>{t('按 FIN 真实站点与楼层示意，无实际比例；图与列表使用同一对象。')}</title>
  {sites.map(({site,floors},index)=>{const count=Math.min(columns,sites.length-Math.floor(index/columns)*columns),x=width/(count+1)*(index%columns+1),y=Math.floor(index/columns)*rowHeight+rowHeight-95,buildingHeight=Math.max(155,floors.length*24),top=y-buildingHeight;
   return <g key={site.id} className="cockpit-building" transform={`translate(${x},0)`} data-native-site={site.nativeId}>
    <path className="cockpit-ground" d={`M-145 ${y-5} L0 ${y-62} L145 ${y-5} L0 ${y+50}Z`}/><path className="cockpit-campus-path" d={`M-145 ${y+20} L0 ${y-36} L145 ${y+20} M-100 ${y-45} L100 ${y+32}`}/>
    <g {...activate(site)} className="cockpit-building-site"><title>{path(site.id)}</title><path className="cockpit-building-left" d={`M-58 ${top} L0 ${top+24} L0 ${y+24} L-58 ${y}Z`}/><path className="cockpit-building-right" d={`M0 ${top+24} L58 ${top} L58 ${y} L0 ${y+24}Z`}/><path className="cockpit-building-roof" d={`M-58 ${top} L0 ${top-24} L58 ${top} L0 ${top+24}Z`}/></g>
    {floors.map((floor,level)=>{const a=top+buildingHeight*(level/floors.length),b=top+buildingHeight*((level+1)/floors.length);return <g key={floor.id} {...activate(floor)} className="cockpit-building-floor"><title>{path(floor.id)}</title><path className="cockpit-floor-left" d={`M-58 ${a} L0 ${a+24} L0 ${b+24} L-58 ${b}Z`}/><path className="cockpit-floor-right" d={`M0 ${a+24} L58 ${a} L58 ${b} L0 ${b+24}Z`}/><path className="cockpit-window" d={`M-47 ${(a+b)/2+3} L-13 ${(a+b)/2+17} M13 ${(a+b)/2+17} L47 ${(a+b)/2+3}`}/><text className="cockpit-floor-label" x="73" y={(a+b)/2+10}>{floor.name}</text></g>;})}
    <text className="cockpit-building-label" x="0" y={y+55} textAnchor="middle">{site.name}</text><text className="cockpit-building-value" x="0" y={y+76} textAnchor="middle">{cockpitMetricValue(site)} {site.unit}</text>
   </g>;
  })}
 </svg></div>;
}
