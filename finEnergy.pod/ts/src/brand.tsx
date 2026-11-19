import {t,subscribeLocale} from './i18n';

export let productName=t('FIN Energy 能源管理');
export let productTagline=t('楼宇能源分析');
subscribeLocale(()=>{productName=t('FIN Energy 能源管理');productTagline=t('楼宇能源分析');});

export function BrandMark(){
 return <svg className="brand-mark" viewBox="0 0 40 44" fill="none" aria-hidden="true"><path d="M20 2 37 12 20 22 3 12Z" fill="#16A59B"/><path d="M3 15 18.5 24V42L3 33Z" fill="#3976BA"/><path d="M21.5 24 37 15V33L21.5 42Z" fill="#7865AF"/><path d="m10 8 17 10M10 19v18m19-18v18" stroke="white" strokeOpacity=".35" strokeWidth="1.2"/></svg>;
}
