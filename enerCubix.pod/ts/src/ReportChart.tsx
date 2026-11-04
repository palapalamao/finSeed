import {useEffect,useRef} from 'react';
import * as echarts from 'echarts/core';
import {BarChart,LineChart,ScatterChart,PieChart} from 'echarts/charts';
import {GridComponent,LegendComponent,TooltipComponent,DataZoomComponent,ToolboxComponent,TitleComponent,MarkLineComponent} from 'echarts/components';
import {CanvasRenderer} from 'echarts/renderers';
import {chartOptions,compactChartOptions,shareChartOptions,type AxisBounds} from './chartOptions';
import type {ReportSnapshot} from './types';
import {locale,t} from './i18n';

echarts.use([BarChart,LineChart,ScatterChart,PieChart,GridComponent,LegendComponent,TooltipComponent,DataZoomComponent,ToolboxComponent,TitleComponent,MarkLineComponent,CanvasRenderer]);
export function ReportChart({snapshot,bounds,shares=false,profileType='bar',colors,dailyColorBy='meter',compact=false}:{compact?:boolean;snapshot:ReportSnapshot;bounds?:AxisBounds;shares?:boolean;profileType?:'bar'|'line';colors?:Record<string,string>;dailyColorBy?:'meter'|'band'}){
 const host=useRef<HTMLDivElement>(null);
 useEffect(()=>{if(!host.current)return;const chart=echarts.init(host.current);
 const options=shares?shareChartOptions(snapshot.result.extra?.utilityShares as Record<string,unknown>[]||[],true,snapshot.display?.objects):chartOptions(snapshot.result,bounds,{type:profileType,colors,names:snapshot.display?.objects,dailyColorBy,request:snapshot.request});chart.setOption(compact&&!shares?compactChartOptions(options):options);const resize=new ResizeObserver(()=>chart.resize());resize.observe(host.current);return()=>{resize.disconnect();chart.dispose();};
 },[snapshot,bounds,shares,profileType,colors,dailyColorBy,compact,locale]);
 return <div ref={host} className="report-chart" role="img" aria-label={t('{0}图表，详细数值见下方数据表',shares?t('分项能耗占比'):snapshot.title)}/>;
}
