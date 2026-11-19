import {useEffect,useMemo,useRef,useState} from 'react';
import {Button,Empty,Space,Tag} from 'antd';
import * as echarts from 'echarts/core';
import {BarChart,LineChart,ScatterChart} from 'echarts/charts';
import {DataZoomComponent,GridComponent,MarkAreaComponent,TitleComponent,TooltipComponent} from 'echarts/components';
import {CanvasRenderer} from 'echarts/renderers';
import {cleaningReason,type CleaningPreview} from './cleaning';
import {cleaningChartData,cleaningChartOption,cleaningZoomRange} from './cleaningChart';
import {t} from './i18n';

echarts.use([BarChart,LineChart,ScatterChart,DataZoomComponent,GridComponent,MarkAreaComponent,TitleComponent,TooltipComponent,CanvasRenderer]);
export function CleaningPreviewChart({preview,unit}:{preview:CleaningPreview;unit:string}){
 const host=useRef<HTMLDivElement>(null),chart=useRef<echarts.ECharts|null>(null);
 const data=useMemo(()=>cleaningChartData(preview),[preview]);const [selected,setSelected]=useState(-1);
 useEffect(()=>{
  setSelected(-1);if(!host.current||!data.hasValues)return;
  const instance=echarts.init(host.current);chart.current=instance;instance.setOption(cleaningChartOption(data,unit));
  const resize=new ResizeObserver(()=>instance.resize());resize.observe(host.current);
  return()=>{resize.disconnect();chart.current=null;instance.dispose();};
 },[data,unit]);
 const locate=()=>{const next=(selected+1)%data.anomalies.length;setSelected(next);chart.current?.dispatchAction({type:'dataZoom',...cleaningZoomRange(data,next)});};
 const reset=()=>{setSelected(-1);chart.current?.dispatchAction({type:'dataZoom',start:0,end:100});};
 const anomaly=data.anomalies[selected];
 const source=anomaly?.detail.pointId;
 return <section className="cleaning-chart-panel" aria-label={t('清洗趋势对照')}>
  <div className="cleaning-chart-toolbar"><h3>{t('清洗趋势对照')}</h3><Space wrap><Tag color={data.anomalies.length?'volcano':'default'}>{t('异常与修正：{0} 处',data.anomalies.length)}</Tag><Button size="small" disabled={!data.anomalies.length||!data.hasValues} onClick={locate}>{t('定位下一处异常')}</Button><Button size="small" disabled={!data.hasValues} onClick={reset}>{t('查看全部')}</Button></Space></div>
  <p>{t('原始读数显示折线，清洗后用量显示柱状图。上下两图共用时间范围，各自使用独立纵轴。可拖动底部滑块或在图内缩放；阴影表示异常或修正区间，空值和 NA 保留为空。')}</p>
  {data.hasValues?<div ref={host} className="cleaning-preview-chart" role="img" aria-label={t('原始读数折线与清洗后用量柱状图')}/>:<Empty description={t('此范围没有可绘制的有效时序数据')}/>}
  {anomaly&&<p className="cleaning-chart-focus" role="status">{t(source?'第 {0} / {1} 处：{2}；{3} 至 {4}；来源：{5}':'第 {0} / {1} 处：{2}；{3} 至 {4}',selected+1,data.anomalies.length,cleaningReason(anomaly.reason),String(anomaly.detail.intervalStart||anomaly.detail.ts),String(anomaly.detail.intervalEnd||anomaly.detail.ts),source)}</p>}
 </section>;
}
