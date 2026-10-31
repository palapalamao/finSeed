import {useEffect,useState} from 'react';
import {Alert} from 'antd';
import type {EnerCubixApi} from './api';
import type {CockpitAsset} from './cockpitAssets';
import {t} from './i18n';
export function CockpitAssetPreview({asset,api,nameForRef,activeRef,onHotspot,onPosition,onReady,onFailure}:{asset:CockpitAsset;api:EnerCubixApi;nameForRef:(id:string)=>string|undefined;activeRef?:string;onHotspot:(id:string)=>void;onPosition?:(x:number,y:number)=>void;onReady?:(displayed:boolean)=>void;onFailure?:()=>void}){
 const [failed,setFailed]=useState(false);
 useEffect(()=>{setFailed(false);onReady?.(false);},[asset.id,asset.hash]);
 const spots=asset.hotspots.filter(hotspot=>nameForRef(hotspot.spaceId));
 return <div className="asset-preview">{failed?<Alert type="warning" showIcon message={t('素材暂不可用，请使用默认示意和对象列表。')}/>:<div className="asset-viewport"><div className="asset-map" style={{width:asset.width/asset.height*560,aspectRatio:asset.width+'/'+asset.height}} onClick={event=>{if(!onPosition)return;const r=event.currentTarget.getBoundingClientRect();onPosition(Math.max(0,Math.min(1,(event.clientX-r.left)/r.width)),Math.max(0,Math.min(1,(event.clientY-r.top)/r.height)));}}><img src={api.assetImageUrl(asset)} alt={asset.name} onLoad={()=>onReady?.(true)} onError={()=>{setFailed(true);onReady?.(false);onFailure?.();}}/>{spots.map((spot,index)=><button type="button" key={spot.spaceId} className="asset-hotspot" style={{left:spot.x*100+'%',top:spot.y*100+'%'}} aria-label={t('热点：{0}',nameForRef(spot.spaceId)!)} aria-pressed={activeRef===spot.spaceId} title={nameForRef(spot.spaceId)} onClick={event=>{event.stopPropagation();onHotspot(spot.spaceId);}}>{index+1}</button>)}</div></div>}{spots.length<asset.hotspots.length&&<p>{t('部分热点对象不在当前可读范围，请使用可用对象列表。')}</p>}</div>;
}
